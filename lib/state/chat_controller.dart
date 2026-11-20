import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/hermes_rpc.dart';
import '../api/models.dart';

enum ChatPhase { starting, idle, running, failed }

/// The bot's forever-chat ("Bot Chat"), as the Hermes dashboard uses it.
///
/// Open: `session.resume` the profile's canonical session (history included),
/// or, on a bot's first-ever chat, `session.create {title: "Bot Chat"}` and
/// claim the title with `session.title`. Then `prompt.submit` -> stream of
/// `message.*` / `tool.*` events -> `message.complete`. The runtime session id
/// changes after a reconnect; the durable id does not.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.rpc,
    required Bot bot,
    this.findCanonical,
    this.onTurnSettled,
  }) {
    _bot = bot;
    _eventSub = rpc.events.listen(_onEvent);
    _requestSub = rpc.serverRequests.listen(_onServerRequest);
    _reconnectSub = rpc.onReconnected.listen((_) => _reattach());
    _statusSub = rpc.statusStream.listen((_) => _notify());
  }

  final HermesRpc rpc;
  late Bot _bot;

  /// Re-reads the roster and returns the bot's current canonical session.
  final Future<SessionSummary?> Function(String profile)? findCanonical;

  /// Called after a turn ends (roster preview / unread bookkeeping).
  final void Function(Bot bot)? onTurnSettled;

  late final StreamSubscription<GatewayEvent> _eventSub;
  late final StreamSubscription<ServerRequest> _requestSub;
  late final StreamSubscription<void> _reconnectSub;
  late final StreamSubscription<ConnectionStatus> _statusSub;

  final List<ChatMessage> messages = [];
  ChatPhase phase = ChatPhase.starting;
  String? error;
  String? statusText;
  String? model;
  String? reasoningEffort;

  String? _sessionId; // runtime id, valid for this socket
  String? _storedId; // durable id, survives reconnects
  ChatMessage? _current; // assistant row being streamed
  bool _segmentBreak = false;
  bool _disposed = false;
  Future<void>? _starting;

  ServerRequest? _approvalRequest;
  PendingApproval? approval;
  ServerRequest? _clarifyRequest;
  List<ClarifyQuestion>? clarify;

  Bot get bot => _bot;
  ConnectionStatus get connection => rpc.status;
  bool get busy => phase == ChatPhase.running;
  bool get ready => _sessionId != null && phase != ChatPhase.starting;

  /// Text of the newest user prompt (pinned at the top of the chat).
  String? get lastPrompt {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.user) return m.text;
    }
    return null;
  }

  void updateBot(Bot bot) {
    _bot = bot;
  }

  Future<void> start() =>
      _starting ??= _open().whenComplete(() => _starting = null);

  /// Re-reads the transcript from the server.
  Future<void> reload() {
    _sessionId = null;
    return start();
  }

  Future<void> _open() async {
    phase = ChatPhase.starting;
    error = null;
    _notify();
    try {
      await rpc.connect();
      final stored = _storedId ?? _bot.canonical?.resumeId;
      if (stored != null) {
        try {
          await _resume(stored);
          return;
        } on RpcException catch (e) {
          // The canonical row vanished (archived, deleted): mint a new one.
          if (e.code != 4001 &&
              e.code != 4004 &&
              !e.message.toLowerCase().contains('not found')) {
            rethrow;
          }
        }
      }
      await _createCanonical();
    } catch (e) {
      phase = ChatPhase.failed;
      error = 'Nepodařilo se otevřít konverzaci: $e';
      _notify();
    }
  }

  Future<void> _resume(String storedId) async {
    final res = await rpc.requestWith('session.resume', {
      'session_id': storedId,
      'profile': _bot.name,
      'close_on_disconnect': false,
      'inline_images': false,
    }, timeout: const Duration(seconds: 90)) as Map;
    _sessionId = res['session_id'] as String?;
    _storedId = (res['stored_session_id'] as String?) ?? storedId;
    _applyInfo(res['info']);
    messages
      ..clear()
      ..addAll(historyToMessages(res['messages']));
    _current = null;
    final running = res['running'] == true || res['inflight'] == true;
    phase = running ? ChatPhase.running : ChatPhase.idle;
    final pending = res['open_requests'];
    if (pending is List) {
      for (final r in pending.whereType<Map>()) {
        // Requests opened before we attached: answer through request.answer.
        final id = r['id'];
        final method = r['method']?.toString();
        final params = r['params'];
        if (id != null && method != null && params is Map) {
          _onServerRequest(
            ServerRequest.detached(
              rpc,
              id,
              method,
              Map<String, dynamic>.from(params)
                ..putIfAbsent('session_id', () => _sessionId),
            ),
          );
        }
      }
    }
    _notify();
  }

  Future<void> _createCanonical() async {
    final res = await rpc.requestWith('session.create', {
      'profile': _bot.name,
      'title': Bot.canonicalTitle,
      'hidden': true,
      'follow_profile_config': true,
      'close_on_disconnect': false,
    }, timeout: const Duration(seconds: 90)) as Map;
    final runtime = res['session_id'] as String?;
    _sessionId = runtime;
    _storedId = (res['stored_session_id'] as String?) ?? runtime;
    _applyInfo(res['info']);
    if (runtime != null) {
      try {
        // Materialize the row and claim the canonical title right away, so a
        // second open (here or in the dashboard) finds it instead of minting
        // a duplicate.
        await rpc.request('session.title', {
          'session_id': runtime,
          'title': Bot.canonicalTitle,
        });
      } on RpcException catch (e) {
        if (e.message.toLowerCase().contains('already in use') &&
            findCanonical != null) {
          // Someone else created the Bot Chat meanwhile: adopt theirs.
          final winner = await findCanonical!(_bot.name);
          if (winner != null) {
            rpc.request('session.close', {'session_id': runtime}).ignore();
            await _resume(winner.resumeId);
            return;
          }
        }
      }
    }
    messages.clear();
    phase = ChatPhase.idle;
    _notify();
  }

  Future<void> _reattach() async {
    final stored = _storedId;
    if (stored == null || _disposed) return;
    final wasRunning = phase == ChatPhase.running;
    try {
      await _resume(stored);
      if (wasRunning && phase != ChatPhase.running) onTurnSettled?.call(_bot);
    } catch (e) {
      error = 'Obnovení po výpadku spojení selhalo: $e';
      _notify();
    }
  }

  /// Maps `session.resume` / `session.history` rows to transcript rows.
  /// Consecutive tool rows fold into one activity line.
  static List<ChatMessage> historyToMessages(Object? rows) {
    final out = <ChatMessage>[];
    if (rows is! List) return out;
    for (final r in rows.whereType<Map>()) {
      final role = r['role']?.toString();
      final time = epochToDate(r['timestamp']);
      final text = (r['text'] ?? r['content'])?.toString() ?? '';
      switch (role) {
        case 'user':
          if (text.trim().isEmpty) continue;
          out.add(ChatMessage(role: ChatRole.user, text: text, time: time));
        case 'assistant':
          if (text.trim().isEmpty) continue;
          out.add(
            ChatMessage(role: ChatRole.assistant, text: text, time: time),
          );
        case 'tool':
          final last = out.isNotEmpty ? out.last : null;
          final row = (last != null && last.role == ChatRole.activity)
              ? last
              : (ChatMessage(role: ChatRole.activity, time: time)
                  ..let(out.add));
          row.tools.add(
            ToolActivity(
              id: r['tool_call_id']?.toString() ?? '${row.tools.length}',
              name: r['name']?.toString() ?? 'tool',
              preview: r['context']?.toString(),
              state: ToolState.done,
            ),
          );
        default:
          // system rows are model scaffolding; skip.
          break;
      }
    }
    return out;
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
    await rpc.requestWith('prompt.submit', {
      'session_id': _sessionId,
      'text': text,
    }, timeout: const Duration(minutes: 5));
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

  static const effortLevels = ['minimal', 'low', 'medium', 'high', 'xhigh'];

  /// Session-scoped reasoning effort (like the dashboard's "Med" chip).
  Future<void> setReasoningEffort(String level) async {
    final sid = _sessionId;
    if (sid == null) return;
    final previous = reasoningEffort;
    reasoningEffort = level;
    _notify();
    try {
      await rpc.request('config.set', {
        'session_id': sid,
        'key': 'reasoning',
        'value': level,
        'scope': 'session',
      });
    } catch (e) {
      reasoningEffort = previous;
      error = 'Změna úrovně uvažování selhala: $e';
      _notify();
    }
  }

  void toggleActivity(ChatMessage m) {
    m.expanded = !m.expanded;
    _notify();
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
      req.respond(
        answers == null ? {} : {'answers': answers, 'outcome': 'submitted'},
      );
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
          choices:
              (p['choices'] as List?)?.map((e) => e.toString()).toList() ??
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
              choices: (q['choices'] as List?)
                  ?.map((e) => e.toString())
                  .toList(),
              multiSelect: q['multi_select'] == true,
            ),
        ];
        _notify();
      default:
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

  /// Tool calls go into the activity row right after the current text; a
  /// later delta then opens a fresh assistant row below it.
  ChatMessage _activityRow() {
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && last.role == ChatRole.activity) return last;
    final cur = _current;
    if (cur != null) {
      cur.streaming = false;
      if (cur.text.isEmpty) messages.remove(cur);
      _current = null;
    }
    final row = ChatMessage(role: ChatRole.activity);
    messages.add(row);
    return row;
  }

  void _onEvent(GatewayEvent ev) {
    if (ev.sessionId == null || ev.sessionId != _sessionId) return;
    final p = ev.payload;
    switch (ev.type) {
      case 'message.start':
        phase = ChatPhase.running;
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
        final t = p['text'];
        final m = _current;
        if (m != null) {
          if (t is String && t.isNotEmpty) m.text = t;
          m.streaming = false;
          if (m.text.isEmpty) messages.remove(m);
          _current = null;
        } else if (t is String &&
            t.isNotEmpty &&
            p['already_streamed'] != true) {
          messages.add(ChatMessage(role: ChatRole.assistant, text: t));
        }
      case 'tool.generating':
        statusText = 'Připravuje ${p['name'] ?? 'nástroj'}…';
      case 'tool.start':
        final row = _activityRow();
        row.tools.add(
          ToolActivity(
            id: p['tool_id']?.toString() ?? '${row.tools.length}',
            name: p['name']?.toString() ?? 'tool',
            preview: (p['preview'] ?? p['context'])?.toString(),
          ),
        );
        statusText = p['name']?.toString();
      case 'tool.progress':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) {
          tool.progress = p['message']?.toString() ?? p['progress']?.toString();
        }
      case 'tool.complete':
        final tool = _findTool(p['tool_id']?.toString());
        if (tool != null) {
          tool.state = p['error'] != null ? ToolState.failed : ToolState.done;
          tool.summary = p['summary']?.toString();
          tool.durationS = (p['duration_s'] as num?)?.toDouble();
          tool.progress = null;
        }
        statusText = null;
      case 'status.update':
        final t = p['text']?.toString();
        statusText = (t == null || t.isEmpty) ? null : t;
      case 'thinking.delta':
        final t = p['text']?.toString();
        if (t != null && t.trim().isNotEmpty) statusText = t.trim();
      case 'session.info':
        _applyInfo(p);
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
        if (t != null && t.isNotEmpty) {
          messages.add(ChatMessage(role: ChatRole.notice, text: t));
        }
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
      final last = messages.isNotEmpty ? messages.last : null;
      // An already-sealed interim row with the same text: don't duplicate it.
      if (m == null &&
          last?.role == ChatRole.assistant &&
          last!.text == finalText) {
        // keep
      } else {
        (m ?? _newAssistant()).text = finalText;
      }
    }
    if (status == 'interrupted') {
      final target = _current ?? m;
      if (target != null) {
        target.interrupted = true;
      } else {
        messages.add(ChatMessage(role: ChatRole.notice, text: 'Přerušeno'));
      }
    } else if (status == 'error') {
      final err = p['error'];
      final msg = err is Map
          ? (err['message'] ?? err.toString())
          : (err ?? 'Odpověď skončila chybou');
      messages.add(ChatMessage(role: ChatRole.error, text: msg.toString()));
    }
    final w = p['warning'];
    if (w is String && w.trim().isNotEmpty) {
      messages.add(ChatMessage(role: ChatRole.notice, text: w.trim()));
    }
    _finishTurn();
    onTurnSettled?.call(_bot);
  }

  void _finishTurn() {
    final m = _current;
    if (m != null) {
      m.streaming = false;
      if (m.text.isEmpty) messages.remove(m);
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
    final r = info['reasoning_effort'];
    if (r is String && r.isNotEmpty) reasoningEffort = r;
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
    // The Bot Chat is a forever-chat: never close it, just detach (the server
    // reaps the idle runtime after its grace period).
    super.dispose();
  }
}

extension _Let<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
