import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_bots/api/hermes_http.dart';
import 'package:hermes_bots/api/hermes_rpc.dart';
import 'package:hermes_bots/api/models.dart';
import 'package:hermes_bots/state/chat_controller.dart';

import 'fake_hermes_server.dart';

Future<void> waitFor(bool Function() cond, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late FakeHermesServer server;

  setUp(() async {
    server = FakeHermesServer();
    await server.start();
  });

  tearDown(() => server.stop());

  Future<HermesHttp> signedIn() async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    await http.postJson('/auth/password-login',
        {'provider': 'basic', 'username': 'u', 'password': 'p', 'next': ''});
    return http;
  }

  test('login stores session cookies and authenticates REST calls', () async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    Map<String, String>? persisted;
    http.onCookiesChanged = (c) => persisted = c;

    await expectLater(
      http.postJson('/auth/password-login',
          {'provider': 'basic', 'username': 'u', 'password': 'bad', 'next': ''}),
      throwsA(isA<HermesHttpException>().having((e) => e.statusCode, 'status', 401)),
    );
    await http.postJson('/auth/password-login',
        {'provider': 'basic', 'username': 'u', 'password': 'p', 'next': ''});

    expect(http.hasSession, isTrue);
    expect(persisted, {
      'hermes_session_at': 'AT1',
      'hermes_session_rt': 'RT1',
      'hermes_session_provider': 'basic',
    });
    final me = await http.getJson('/api/auth/me');
    expect(me['user_id'], 'u');
    http.close();
  });

  test('profiles parse into bots with display-name fallback', () async {
    final http = await signedIn();
    final res = await http.getJson('/api/profiles') as Map;
    final bots = (res['profiles'] as List).cast<Map<String, dynamic>>().map(Bot.fromJson).toList();
    expect(bots.map((b) => b.displayName), ['zeta', 'Hermes']);
    expect(bots[1].isDefault, isTrue);
    expect(bots[1].model, 'hermes-4');
    expect(bots[1].initials, 'H');
    http.close();
  });

  test('chat: ticket handshake, session.create, streamed reply with tools', () async {
    final http = await signedIn();
    final rpc = HermesRpc(http);
    final bot = Bot(name: 'default', displayName: 'Hermes', description: '');
    final chat = ChatController(rpc: rpc, bot: bot);

    await chat.start();
    expect(chat.phase, ChatPhase.idle);
    expect(chat.model, 'hermes-4');
    expect(server.capabilitiesAnnounced, isTrue);
    expect(server.lastWsOrigin, isNull, reason: 'native client must not send a foreign Origin');
    final create = server.received.firstWhere((m) => m['method'] == 'session.create');
    expect(create['params'], {'profile': 'default', 'close_on_disconnect': false});

    await chat.send('Ahoj');
    await waitFor(() => chat.phase == ChatPhase.idle);

    expect(chat.messages.map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
    final reply = chat.messages.last;
    expect(reply.text, 'Ahoj, svete!');
    expect(reply.streaming, isFalse);
    expect(reply.tools.single.name, 'web_search');
    expect(reply.tools.single.state, ToolState.done);
    final submit = server.received.firstWhere((m) => m['method'] == 'prompt.submit');
    expect(submit['params'], {'session_id': 'rt1', 'text': 'Ahoj'});

    chat.dispose();
    await rpc.dispose();
    http.close();
  });

  test('chat: approval request is surfaced and answered', () async {
    server.askApproval = true;
    final http = await signedIn();
    final rpc = HermesRpc(http);
    final chat = ChatController(
        rpc: rpc, bot: Bot(name: 'default', displayName: 'Hermes', description: ''));
    await chat.start();

    unawaited(chat.send('do it'));
    await waitFor(() => chat.approval != null);
    expect(chat.approval!.command, 'ls /');
    expect(chat.approval!.choices, ['once', 'deny']);

    chat.answerApproval('once');
    expect(await server.approvalAnswer.future, {'choice': 'once'});
    await waitFor(() => chat.phase == ChatPhase.idle);
    expect(chat.messages.last.text, 'Ahoj, svete!');
    expect(chat.approval, isNull);

    chat.dispose();
    await rpc.dispose();
    http.close();
  });

  test('ws-ticket without session reports unauthorized', () async {
    final http = HermesHttp(baseUrl: server.baseUrl);
    final rpc = HermesRpc(http);
    var expired = false;
    rpc.onUnauthorized = () => expired = true;
    await expectLater(rpc.connect(), throwsA(isA<HermesHttpException>()));
    expect(expired, isTrue);
    await rpc.dispose();
    http.close();
  });
}
