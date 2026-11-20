import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// In-process stand-in for a gated Hermes dashboard: cookie login, ws-ticket,
/// and a JSON-RPC `/api/ws` socket that streams a scripted reply.
class FakeHermesServer {
  late HttpServer _server;
  final Set<String> _tickets = {};
  final List<Map<String, dynamic>> received = [];
  String? lastWsOrigin;
  bool capabilitiesAnnounced = false;
  int sessionCounter = 0;
  final List<Map<String, dynamic>> createParams = [];
  final List<String> titled = [];
  final List<String> resumed = [];
  final List<Map<String, dynamic>> configSets = [];

  /// Rows returned by `profiles.list` (RPC) and `/api/profiles` (REST).
  List<Map<String, dynamic>> roster = [
    {
      'name': 'cto',
      'display_name': 'dev-cto',
      'ui_meta': {
        'hermes-bots': {
          'title': 'CTO',
          'sectionId': 's1',
          'sectionName': 'Vibee.one',
          'pinned': true,
          'color': '#F0997B',
          'shape': 'circle',
        },
      },
      'canonical_session': {
        'id': 'botchat-root',
        'resolved_id': 'botchat-tip',
        'preview': 'Analytik overil zdroje',
        'last_active': 1795187000,
        'message_count': 12,
      },
    },
    {
      'name': 'default',
      'display_name': '',
      'is_default': true,
      'model': 'hermes-4',
    },
    {
      'name': 'ghost',
      'ui_meta': {
        'hermes-bots': {'hidden': true},
      },
    },
  ];

  /// Transcript returned by `session.resume`.
  List<Map<String, dynamic>> history = [
    {'role': 'user', 'text': 'nastav monitoring', 'timestamp': 1795186000},
    {'role': 'tool', 'name': 'skill_view', 'context': 'vibee-market-listening'},
    {'role': 'tool', 'name': 'terminal', 'context': 'crontab -l'},
    {
      'role': 'assistant',
      'text': 'Monitoring sverim Analytikovi.',
      'timestamp': 1795186100,
    },
    {'role': 'system', 'text': 'scaffolding'},
  ];

  /// When true, the next prompt triggers an approval request before replying.
  bool askApproval = false;
  final Completer<Map<String, dynamic>> approvalAnswer = Completer();

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  bool _authed(HttpRequest r) =>
      (r.headers.value(HttpHeaders.cookieHeader) ?? '').contains(
        'hermes_session_at=AT1',
      );

  Future<void> _json(
    HttpRequest r,
    int status,
    Object body, {
    List<String> cookies = const [],
  }) async {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    for (final c in cookies) {
      r.response.headers.add(HttpHeaders.setCookieHeader, c);
    }
    r.response.write(jsonEncode(body));
    await r.response.close();
  }

  Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path;
    if (path == '/auth/password-login' && r.method == 'POST') {
      final body = jsonDecode(await utf8.decodeStream(r)) as Map;
      if (body['provider'] == 'basic' &&
          body['username'] == 'u' &&
          body['password'] == 'p') {
        return _json(
          r,
          200,
          {'ok': true, 'next': '/'},
          cookies: [
            'hermes_session_at=AT1; HttpOnly; Path=/; Max-Age=43200; SameSite=Lax',
            'hermes_session_rt=RT1; HttpOnly; Path=/; Max-Age=2592000; SameSite=Lax',
            'hermes_session_provider=basic; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT',
          ],
        );
      }
      return _json(r, 401, {'detail': 'Invalid credentials'});
    }
    if (path == '/api/ws' && WebSocketTransformer.isUpgradeRequest(r)) {
      final ticket = r.uri.queryParameters['ticket'];
      lastWsOrigin = r.headers.value('origin');
      if (ticket == null || !_tickets.remove(ticket)) {
        r.response.statusCode = 403;
        return r.response.close();
      }
      final ws = await WebSocketTransformer.upgrade(r);
      return _serveWs(ws);
    }
    if (!_authed(r)) {
      return _json(r, 401, {'error': 'unauthenticated', 'reason': 'no_cookie'});
    }
    switch (path) {
      case '/api/auth/me':
        return _json(r, 200, {'user_id': 'u', 'provider': 'basic'});
      case '/api/auth/ws-ticket':
        final t =
            'T${_tickets.length + 1}${DateTime.now().microsecondsSinceEpoch}';
        _tickets.add(t);
        return _json(r, 200, {'ticket': t, 'ttl_seconds': 30});
      case '/api/profiles':
        return _json(r, 200, {'profiles': roster});
    }
    return _json(r, 404, {'detail': 'not found'});
  }

  void _serveWs(WebSocket ws) {
    void send(Map<String, dynamic> m) =>
        ws.add(jsonEncode({'jsonrpc': '2.0', ...m}));
    void event(String type, String sid, [Map<String, dynamic>? payload]) =>
        send({
          'method': 'event',
          'params': {'type': type, 'session_id': sid, 'payload': ?payload},
        });

    send({
      'method': 'event',
      'params': {
        'type': 'gateway.ready',
        'payload': {'heartbeat': true},
      },
    });

    ws.listen((data) async {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      received.add(msg);
      final id = msg['id'];
      final method = msg['method'] as String?;
      final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};
      if (method == null) {
        // Response to a server request.
        if (id == 'srq-approval' && !approvalAnswer.isCompleted) {
          approvalAnswer.complete(
            (msg['result'] as Map).cast<String, dynamic>(),
          );
        }
        return;
      }
      switch (method) {
        case 'client.capabilities':
          capabilitiesAnnounced = params['server_requests'] == true;
          send({
            'id': id,
            'result': {
              'server_requests': ['approval', 'clarify'],
            },
          });
        case 'gateway.ping':
          send({
            'id': id,
            'result': {'ok': true},
          });
        case 'profiles.list':
          send({
            'id': id,
            'result': {'profiles': roster, 'bot_mode_protocol': true},
          });
        case 'session.create':
          sessionCounter++;
          createParams.add(params);
          send({
            'id': id,
            'result': {
              'session_id': 'rt$sessionCounter',
              'stored_session_id': 'st$sessionCounter',
              'message_count': 0,
              'messages': [],
              'info': {
                'model': 'hermes-4',
                'reasoning_effort': 'medium',
                'profile_name': params['profile'],
              },
            },
          });
        case 'session.title':
          titled.add(params['title'] as String);
          send({
            'id': id,
            'result': {'title': params['title']},
          });
        case 'session.resume':
          resumed.add(params['session_id'] as String);
          sessionCounter++;
          send({
            'id': id,
            'result': {
              'session_id': 'rt$sessionCounter',
              'stored_session_id': params['session_id'],
              'running': false,
              'messages': history,
              'info': {'model': 'hermes-4', 'reasoning_effort': 'high'},
            },
          });
        case 'config.set':
          configSets.add(params);
          send({
            'id': id,
            'result': {'key': params['key'], 'value': params['value']},
          });
        case 'cron.manage':
          send({
            'id': id,
            'result': {
              'success': true,
              'jobs': [
                {
                  'job_id': 'j1',
                  'name': 'Vibee poptavky',
                  'schedule': '0 9 * * 1-5',
                  'enabled': true,
                  'state': 'scheduled',
                  'next_run_at': '2026-11-23T09:00:00+01:00',
                },
              ],
            },
          });
        case 'session.close':
          send({
            'id': id,
            'result': {'closed': true},
          });
        case 'prompt.submit':
          final sid = params['session_id'] as String;
          send({
            'id': id,
            'result': {'status': 'streaming'},
          });
          event('message.start', sid);
          if (askApproval) {
            send({
              'id': 'srq-approval',
              'method': 'approval',
              'params': {
                'session_id': sid,
                'command': 'ls /',
                'description': 'list root',
                'choices': ['once', 'deny'],
              },
            });
            await approvalAnswer.future;
          }
          event('message.delta', sid, {'text': 'Ahoj, '});
          event('tool.start', sid, {
            'tool_id': 't1',
            'name': 'web_search',
            'preview': 'q',
          });
          event('tool.complete', sid, {
            'tool_id': 't1',
            'name': 'web_search',
            'duration_s': 0.4,
          });
          event('message.delta', sid, {'text': null});
          event('message.delta', sid, {'text': 'svete'});
          event('message.complete', sid, {
            'text': 'Ahoj, svete!',
            'status': 'complete',
          });
        default:
          send({
            'id': id,
            'error': {'code': 4000, 'message': 'unknown method $method'},
          });
      }
    });
  }
}
