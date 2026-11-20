import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobs/api/hermes_rpc.dart';
import 'package:hobs/l10n/strings.dart';
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
      app.hobs.isNotEmpty &&
      !app.loadingHobs &&
      app.connection == ConnectionStatus.connected,
);

/// Secure storage that always fails, like a keychain the app may not use.
class BrokenKeychain extends FlutterSecureStorage {
  const BrokenKeychain();

  static Never _fail() =>
      throw PlatformException(code: '-34018', message: 'keychain unavailable');

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _fail();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _fail();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _fail();
}

/// Secrets go to an in-memory fake keychain; prefs hold only non-secret data.
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

  Future<void> seed({
    Map<String, String> secrets = const {},
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'server_url': server.baseUrl.toString(),
      'username': 'u',
      ...prefs,
    });
    FlutterSecureStorage.setMockInitialValues(Map.of(secrets));
  }

  Future<Set<String>> prefsKeys() async =>
      (await SharedPreferences.getInstance()).getKeys();

  test('login remembers the password, logout keeps it but stays out', () async {
    await seed();
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
    await seed(secrets: {'password': 'old'});
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
    await seed(secrets: {'password': 'p'});
    final app = AppState(store: CredentialsStore());
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    await settle(app);
    app.dispose();
  });

  test('expired session cookies are renewed with the saved password', () async {
    await seed(
      secrets: {
        'password': 'p',
        'session_cookies': '{"hermes_session_at":"STALE"}',
      },
    );
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.init();
    expect(app.phase, AuthPhase.signedIn);
    expect((await store.cookies())['hermes_session_at'], 'AT1');
    await settle(app);
    app.dispose();
  });

  test('a rejected saved password is forgotten and explained', () async {
    await seed(secrets: {'password': 'wrong'});
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.init();
    expect(app.phase, AuthPhase.signedOut);
    expect(app.authError, Strings.current.savedPasswordExpired);
    expect(await store.password(), isNull);
    app.dispose();
  });

  test('secrets never land in prefs', () async {
    await seed();
    final store = CredentialsStore();
    final app = AppState(store: store);
    await app.login(
      serverUrl: server.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    await settle(app);
    expect(await store.password(), 'p');
    expect(await prefsKeys(), isNot(contains('password')));
    expect(await prefsKeys(), isNot(contains('session_cookies')));
    app.dispose();
  });

  test(
    'a plain-text copy from an older build moves into the keychain',
    () async {
      await seed(
        prefs: {
          'password': 'p',
          'session_cookies': '{"hermes_session_at":"STALE"}',
        },
      );
      final store = CredentialsStore();
      expect(await store.password(), 'p');
      expect(await store.cookies(), {'hermes_session_at': 'STALE'});
      expect(await prefsKeys(), isNot(contains('password')));
      expect(await prefsKeys(), isNot(contains('session_cookies')));
      expect(
        await CredentialsStore().password(),
        'p',
        reason: 'a fresh store reads it back from the keychain',
      );
    },
  );

  test('without a keychain secrets stay in memory, never on disk', () async {
    await seed(prefs: {'password': 'old-plain'});
    final store = CredentialsStore(secure: const BrokenKeychain());
    expect(await store.password(), 'old-plain', reason: 'usable this run');
    expect(await prefsKeys(), isNot(contains('password')));

    final app = AppState(store: store);
    await app.login(
      serverUrl: server.baseUrl.toString(),
      username: 'u',
      password: 'p',
    );
    expect(app.phase, AuthPhase.signedIn);
    await settle(app);
    expect(await store.password(), 'p');
    expect(await prefsKeys(), isNot(contains('password')));
    expect(await prefsKeys(), isNot(contains('session_cookies')));
    expect(
      await CredentialsStore(secure: const BrokenKeychain()).password(),
      isNull,
      reason: 'nothing survives a restart',
    );
    app.dispose();
  });
}
