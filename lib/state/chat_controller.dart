import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';

enum ChatPhase { starting, idle, running, failed }

/// One conversation with one bot (Hermes profile).
///
/// Lifecycle: `session.create {profile}` -> `prompt.submit` -> stream of
/// `message.*` / `tool.*` events -> `message.complete`. The runtime session id
/// changes after a reconnect (`session.resume` with the durable stored id).
class ChatController extends ChangeNotifier {
  ChatController({required this.rpc, required this.bot}) {
    _eventSub = rpc.events.listen(_onEvent);
    _requestSub = rpc.serverRequests.listen(_onServerRequest);
    _reconnectSub = rpc.onReconnected.listen((_) => _reattach());
    _statusSub = rpc.statusStream.listen((_) => notifyListeners());
  }

  final HermesRpc rpc;
  final Bot bot;

  late final StreamSubscription<GatewayEvent> _eventSub;
  late final StreamSubscription<ServerRequest> _requestSub;
  late final StreamSubscription<void> _reconnectSub;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  final List<ChatMessage> messages = [];
  ChatPhase phase = ChatPhase.starting;
  String? error;
  String? statusText;
  String? model;
  String? title;

  String? _sessionId; // runtime id, valid for this socket
  String? _storedId; // durable id, survives reconnects
  ChatMessage? _current; // assistant bubble being streamed
  bool _segmentBreak = false;
  bool _disposed = false;

  ServerRequest? _approvalRequest;
  PendingApproval? approval;
  ServerRequest? _clarifyRequest;
  List<ClarifyQuestion>? clarify;

  ConnectionStatus get connection => rpc.status;
  bool get busy => phase == ChatPhase.running;
  bool get ready => _sessionId != null && phase != ChatPhase.starting;

  /// Creates a fresh session bound to [bot].
  Future<void> start() async {
    phase = ChatPhase.starting;
    error = null;
    _notify();
    try {
      await rpc.connect();
      final res = await rpc.requestWith(
        'session.create',
        {'profile': bot.name, 'close_on_disconnect': false},
        timeout: const Duration(seconds: 90),
      ) as Map;
      _sessionId = res['session_id'] as String?;
      _storedId = res['stored_session_id'] as String? ?? _sessionId;
      _applyInfo(res['info']);
      phase = ChatPhase.idle;
    } catch (e) {
      phase = ChatPhase.failed;
      error = 'Nepodařilo se otevřít konverzaci: $e';
    }
    _notify();
  }

  /// Drops the current conversation and starts a new one with the same bot.
  Future<void> reset() async {
    final old = _sessionId;
    _sessionId = null;
    _storedId = null;
    messages.clear();
    _current = null;
    _clearPrompts();
    if (old != null) {
      rpc.request('session.close', {'session_id': old}).catchError((_) => null);
    }
    await start();
  }

  Future<void> _reattach() async {
    final stored = _storedId;
    if (stored == null || _disposed) return;
    try {
      final res = await rpc.requestWith(
        'session.resume',
        {'session_id': stored, 'profile': bot.name},
        timeout: const Duration(seconds: 90),
      ) as Map;
      _sessionId = res['session_id'] as String?;
      final running = res['running'] == true || res['inflight'] == true;
      if (!running && phase == ChatPhase.running) {
        // The turn finished while we were offline; reload its final text.
        _adoptHistoryTail(res['messages']);
        _finishTurn();
      }
      _notify();
    } catch (e) {
      error = 'Obnovení po výpadku spojení selhalo: $e';
      _notify();
    }
  }

  void _adoptHistoryTail(Object? msgs) {
    if (msgs is! List || msgs.isEmpty) return;
    final last = msgs.last;
    if (last is! Map || last['role'] != 'assistant') return;
    final text = last['content'] ?? last['text'];
    if (text is String && text.isNotEmpty) {
      final bubble = _current ?? _newAssistant();
      bubble.text = text;
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_sessionId == null) {
      error = 'Konverzace není připravená.';
      _notify();
      return;
    }
    messages.add(ChatMessage(role: ChatRole.user, text: trimmed));
    phase = ChatPhase.running;
    error = null;
    statusText = null;
    _notify();
    try {
      await _submit(trimmed);
    } on RpcException catch (e) {
      if (e.isSessionGone && _storedId != null) {
        await _reattach();
        try {
          await _submit(trimmed);
          return;
        } catch (e2) {
          _failTurn('$e2');
          return;
        }
      }
      _failTurn(e.message);
    } catch (e) {
      _failTurn('$e');
    }
  }

  Future<void> _submit(String text) async {
    await rpc.requestWith(
      'prompt.submit',
      {'session_id': _sessionId, 'text': text},
      timeout: const Duration(minutes: 5),
    );
  }

  Future<void> interrupt() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await rpc.request('session.interrupt', {'session_id': sid});
    } catch (e) {
      error = 'Přerušení selhalo: $e';
      _notify();
    }
  }

  // --- approvals / clarify -------------------------------------------------

  void answerApproval(String choice) {
    _approvalRequest?.respond({'choice': choice});
    _approvalRequest = null;
    approval = null;
    _notify();
  }

  void answerClarify(Map<String, String?>? answers) {
    final req = _clarifyRequest;
    if (req != null) {
      req.respond(answers == null ? {} : {'answers': answers, 'outcome': 'submitted'});
    }
    _clarifyRequest = null;
    clarify = null;
    _notify();
  }

  void _clearPrompts() {
    _approvalRequest = null;
    approval = null;
    _clarifyRequest = null;
    clarify = null;
  }

  void _onServerRequest(ServerRequest req) {
    if (req.sessionId == null || req.sessionId != _sessionId) return;
    final p = req.params;
    switch (req.method) {
      case 'approval':
        _approvalRequest = req;
        approval = PendingApproval(
          command: p['command']?.toString() ?? '',
          description: p['description']?.toString() ?? '',
          choices: (p['choices'] as List?)?.map((e) => e.toString()).toList() ??
              const ['once', 'deny'],
          toolName: p['tool_name']?.toString(),
        );
        _notify();
      case 'clarify':
        final qs = (p['questions'] as List?) ?? const [];
        _clarifyRequest = req;
        clarify = [
          for (final q in qs.whereType<Map>())
            ClarifyQuestion(
              qid: q['qid']?.toString() ?? '',
              question: q['question']?.toString() ?? '',
              choices: (q['choices'] as List?)?.map((e) => e.toString()).toList(),
              multiSelect: q['multi_select'] == true,
            ),
        ];
        _notify();
      default:
        // Only one session listener should decline; leave others to their owner.
        break;
    }
  }

  // --- events --------------------------------------------------------------

  ChatMessage _newAssistant() {
    final m = ChatMessage(role: ChatRole.assistant, streaming: true);
    messages.add(m);
    _current = m;
    _segmentBreak = false;
    return m;
  }

  void _onEvent(GatewayEvent ev) {
    if (ev.sessionId == null || ev.sessionId != _sessionId) return;
    final p = ev.payload;
    switch (ev.type) {
      case 'message.start':
        phase = ChatPhase.running;
        _current ??= _newAssistant();
      case 'message.delta':
        final t = p['text'];
        if (t is String) {
          final m = _current ?? _newAssistant();
          if (_segmentBreak && m.text.isNotEmpty && !m.text.endsWith('\n')) {
            m.text += '\n\n';
          }
          _segmentBreak = false;
          m.text += t;
          statusText = null;
        } else {
          _segmentBreak = true;
        }
      case 'message.interim':
        // Sealed commentary beside tool calls: freeze this bubble, the next
        // delta opens a new one.
        final t = p['text'];
        final m = _current;
        if (m != null) {
          if (t is String && t.isNotEmpty) m.text = t;
          m.streaming = false;
          if (m.text.isEmpty && m.tools.isEmpty) messages.remove(m);
          _current = null;
        } else if (t is String && t.isNotEmpty && p['already_streamed'] != true) {
          messages.add(ChatMessage(role: ChatRole.assistant, text: t));
        }
      case 'tool.generating':
        statusText = 'Připravuje nástroj ${p['name'] ?? ''}…';
      case 'tool.start':
        final m = _current ?? _newAssistant();
        m.tools.add(ToolActivity(
          id: p['tool_id']?.toString() ?? '${m.tools.length}',
          name: p['name']?.toString() ?? 'tool',
          preview: (p['preview'] ?? p['context'])?.toString(),
        ));
        statusText = null;
      case 'tool.progress':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) tool.progress = p['message']?.toString() ?? p['progress']?.toString();
      case 'tool.complete':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) {
          tool.state = p['error'] != null ? ToolState.failed : ToolState.done;
          tool.summary = p['summary']?.toString();
          tool.durationS = (p['duration_s'] as num?)?.toDouble();
          tool.progress = null;
        }
      case 'status.update':
        final t = p['text']?.toString();
        statusText = (t == null || t.isEmpty) ? null : t;
      case 'thinking.delta':
        final t = p['text']?.toString();
        if (t != null && t.trim().isNotEmpty) statusText = t.trim();
      case 'session.info':
        _applyInfo(p);
      case 'session.title':
        title = p['title']?.toString() ?? title;
      case 'message.complete':
        _completeTurn(p);
      case 'request.cancel':
        final id = p['id'];
        if (_approvalRequest?.id == id) {
          _approvalRequest = null;
          approval = null;
        }
        if (_clarifyRequest?.id == id) {
          _clarifyRequest = null;
          clarify = null;
        }
      case 'approval.cancelled':
        _approvalRequest = null;
        approval = null;
      case 'error':
        final msg = p['message']?.toString() ?? 'Neznámá chyba';
        messages.add(ChatMessage(role: ChatRole.error, text: msg));
        if (phase == ChatPhase.running) _finishTurn();
      case 'notice':
        final t = (p['text'] ?? p['message'])?.toString();
        if (t != null && t.isNotEmpty) messages.add(ChatMessage(role: ChatRole.notice, text: t));
      default:
        return; // ignore without repaint
    }
    _notify();
  }

  ToolActivity? _findTool(String? id) {
    for (final m in messages.reversed) {
      for (final t in m.tools) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  void _completeTurn(Map<String, dynamic> p) {
    final status = p['status']?.toString() ?? 'complete';
    final finalText = (p['text'] as String?)?.isNotEmpty == true
        ? p['text'] as String
        : (p['rendered'] as String? ?? '');
    final m = _current;
    if (finalText.isNotEmpty) {
      (m ?? _newAssistant()).text = finalText;
    }
    if (status == 'interrupted') {
      (_current ?? m)?.interrupted = true;
      if (_current == null && m == null) {
        messages.add(ChatMessage(role: ChatRole.notice, text: 'Přerušeno'));
      }
    } else if (status == 'error') {
      final err = p['error'];
      final msg = err is Map ? (err['message'] ?? err.toString()) : (err ?? 'Odpověď skončila chybou');
      messages.add(ChatMessage(role: ChatRole.error, text: msg.toString()));
    }
    final w = p['warning'];
    if (w is String && w.trim().isNotEmpty) {
      messages.add(ChatMessage(role: ChatRole.notice, text: w.trim()));
    }
    _finishTurn();
  }

  void _finishTurn() {
    final m = _current;
    if (m != null) {
      m.streaming = false;
      if (m.text.isEmpty && m.tools.isEmpty) messages.remove(m);
    }
    for (final msg in messages) {
      msg.streaming = false;
      for (final t in msg.tools) {
        if (t.state == ToolState.running) t.state = ToolState.done;
      }
    }
    _current = null;
    _clearPrompts();
    statusText = null;
    phase = ChatPhase.idle;
  }

  void _failTurn(String msg) {
    messages.add(ChatMessage(role: ChatRole.error, text: msg));
    _finishTurn();
    _notify();
  }

  void _applyInfo(Object? info) {
    if (info is! Map) return;
    final m = info['model'];
    if (m is String && m.isNotEmpty) model = m;
    final t = info['title'];
    if (t is String && t.isNotEmpty) title = t;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSub.cancel();
    _requestSub.cancel();
    _reconnectSub.cancel();
    _statusSub.cancel();
    final sid = _sessionId;
    if (sid != null && rpc.status == ConnectionStatus.connected) {
      rpc.request('session.close', {'session_id': sid}).catchError((_) => null);
    }
    super.dispose();
  }
}
