import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/state/app_state.dart';
import 'package:hobs/state/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_hermes_server.dart';

Future<void> waitFor(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('not met');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Lets the post-login roster fetch and socket handshake finish before the
/// test logs out or disposes.
Future<void> settle(AppState app) => waitFor(
  () =>
      app.bots.isNotEmpty &&
      !app.loadingBots &&
      app.connection == ConnectionStatus.connected,
);

/// No keychain plugin is registered in tests, so [CredentialsStore] runs on
/// its prefs fallback here — the same path an unsigned macOS build takes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding fakes every HttpClient; talk to the real fake server instead.
  HttpOverrides.global = null;
  late FakeHermesServer server;

  setUp(() async {
    server = FakeHermesServer();
    await server.start();
  });

  tearDown(() => server.stop());

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      'server_url': server.baseUrl.toString(),
      'username': 'u',
      ...values,
    });
  }

  test('login remembers the password, logout keeps it but stays out', () async {
    await seed({});
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.init();
    expect(app.phase, AuthPhase.signedOut);

    await app.login(
      serverUrl: server.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    expect(app.phase, AuthPhase.signedIn);
    expect(await store.password(), 'p');
    expect(await store.autoLogin(), isTrue);
    await settle(app);

    await app.logout();
    expect(app.phase, AuthPhase.signedOut);
    expect(await store.password(), 'p', reason: 'prefills the login form');
    expect(await store.autoLogin(), isFalse);

    final again = AppState(store: store);
    await again.init();
    expect(again.phase, AuthPhase.signedOut);
    expect(again.savedPassword, 'p');
    app.dispose();
    again.dispose();
  });

  test('unchecked "remember" does not keep the password', () async {
    await seed({'password': 'old'});
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.login(
      serverUrl: server.baseUrl.toString(),
      username: 'u',
      password: 'p',
      rememberPassword: false,
    );
    expect(await store.password(), isNull);
    await settle(app);
    app.dispose();
  });

  test('startup without a session signs in with the saved password', () async {
    await seed({'password': 'p'});
    final app = AppState(store: CredentialsStore());
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    await settle(app);
    app.dispose();
  });

  test('expired session cookies are renewed with the saved password', () async {
    await seed({
      'password': 'p',
      'session_cookies': '{"hermes_session_at":"STALE"}',
    });
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    expect((await store.cookies())['hermes_session_at'], 'AT1');
    await settle(app);
    app.dispose();
  });

  test('a rejected saved password is forgotten and explained', () async {
    await seed({'password': 'wrong'});
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.init();
    expect(app.phase, AuthPhase.signedOut);
    expect(app.authError, contains('heslo'));
    expect(await store.password(), isNull);
    app.dispose();
  });
}
