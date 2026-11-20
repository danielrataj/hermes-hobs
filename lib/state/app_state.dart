import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/hermes_http.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import 'chat_controller.dart';
import 'credentials_store.dart';

enum AuthPhase { loading, signedOut, signedIn }

/// App-wide state: login, the bot (profile) list, and one live
/// [ChatController] per bot that survives navigating away from the chat.
class AppState extends ChangeNotifier {
  AppState({CredentialsStore? store}) : _store = store ?? CredentialsStore();

  final CredentialsStore _store;

  AuthPhase phase = AuthPhase.loading;
  String serverUrl = CredentialsStore.defaultServer;
  String username = '';

  HermesHttp? _http;
  HermesRpc? _rpc;
  StreamSubscription<ConnectionStatus>? _statusSub;

  List<Bot> bots = [];
  bool loadingBots = false;
  String? botsError;
  final Map<String, ChatController> _chats = {};

  HermesRpc? get rpc => _rpc;
  ConnectionStatus get connection => _rpc?.status ?? ConnectionStatus.disconnected;

  Future<void> init() async {
    serverUrl = await _store.serverUrl();
    username = await _store.username();
    final cookies = await _store.cookies();
    if (cookies.isEmpty) {
      phase = AuthPhase.signedOut;
      notifyListeners();
      return;
    }
    _setupClients(Uri.parse(serverUrl), cookies);
    try {
      await _http!.getJson('/api/auth/me');
      phase = AuthPhase.signedIn;
      notifyListeners();
      unawaited(refreshBots());
      _rpc!.connect().catchError((_) {});
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        await _teardown(clearCookies: true);
        phase = AuthPhase.signedOut;
      } else {
        // Offline / server down: stay signed in, let the user retry.
        phase = AuthPhase.signedIn;
        botsError = describeError(e);
      }
      notifyListeners();
    }
  }

  void _setupClients(Uri base, Map<String, String> cookies) {
    final http = HermesHttp(baseUrl: base, cookies: cookies);
    http.onCookiesChanged = (c) => _store.saveCookies(c);
    final rpc = HermesRpc(http)..onUnauthorized = _onSessionExpired;
    _statusSub = rpc.statusStream.listen((_) => notifyListeners());
    _http = http;
    _rpc = rpc;
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await _teardown(clearCookies: true);
    final base = Uri.parse(serverUrl);
    _setupClients(base, {});
    try {
      await _http!.postJson('/auth/password-login', {
        'provider': 'basic',
        'username': username,
        'password': password,
        'next': '',
      });
      if (!_http!.hasSession) {
        throw HermesHttpException(500, 'Server nevrátil session cookie');
      }
    } catch (e) {
      await _teardown(clearCookies: true);
      rethrow;
    }
    this.serverUrl = serverUrl;
    this.username = username;
    await _store.saveLogin(serverUrl: serverUrl, username: username);
    phase = AuthPhase.signedIn;
    notifyListeners();
    unawaited(refreshBots());
    _rpc!.connect().catchError((_) {});
  }

  Future<void> logout() async {
    final http = _http;
    if (http != null) {
      try {
        await http.postJson('/auth/logout', null);
      } catch (_) {
        // 302 to /login or network error: cookies are dropped locally anyway.
      }
    }
    await _teardown(clearCookies: true);
    phase = AuthPhase.signedOut;
    notifyListeners();
  }

  void _onSessionExpired() {
    if (phase != AuthPhase.signedIn) return;
    _teardown(clearCookies: true).then((_) {
      phase = AuthPhase.signedOut;
      botsError = null;
      notifyListeners();
    });
  }

  Future<void> _teardown({required bool clearCookies}) async {
    for (final c in _chats.values) {
      c.dispose();
    }
    _chats.clear();
    await _statusSub?.cancel();
    _statusSub = null;
    await _rpc?.dispose();
    _rpc = null;
    if (clearCookies) {
      _http?.clearCookies();
      await _store.saveCookies({});
    }
    _http?.close();
    _http = null;
    bots = [];
  }

  Future<void> refreshBots() async {
    final http = _http;
    if (http == null) return;
    loadingBots = true;
    botsError = null;
    notifyListeners();
    try {
      final res = await http.getJson('/api/profiles') as Map;
      final list = (res['profiles'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Bot.fromJson)
          .where((b) => b.name.isNotEmpty)
          .toList()
        ..sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
      bots = list;
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        _onSessionExpired();
        return;
      }
      botsError = describeError(e);
    } finally {
      loadingBots = false;
      notifyListeners();
    }
  }

  /// Returns the live chat for [bot], creating and starting it on first use.
  ChatController chatFor(Bot bot) {
    final existing = _chats[bot.name];
    if (existing != null) return existing;
    final c = ChatController(rpc: _rpc!, bot: bot);
    _chats[bot.name] = c;
    unawaited(c.start());
    // Called from build(): repaint the list badge after this frame.
    Future.microtask(notifyListeners);
    return c;
  }

  bool hasChat(Bot bot) => _chats.containsKey(bot.name);

  void onAppResumed() => _rpc?.reconnectNow();

  static String describeError(Object e) {
    if (e is HermesHttpException) {
      switch (e.statusCode) {
        case 401:
          return 'Neplatné jméno nebo heslo.';
        case 404:
          return 'Server nepodporuje přihlášení heslem (provider "basic").';
        case 429:
          return 'Příliš mnoho pokusů, chvíli počkej.';
        case 503:
          return 'Server je nedostupný (503).';
      }
      return 'Chyba serveru: ${e.message}';
    }
    if (e is SocketException) return 'Server nedostupný: ${e.message}';
    if (e is HandshakeException) return 'TLS chyba: ${e.message}';
    if (e is TimeoutException) return 'Vypršel časový limit.';
    if (e is FormatException) return 'Neplatná adresa serveru.';
    return e.toString();
  }

  @override
  void dispose() {
    _teardown(clearCookies: false);
    super.dispose();
  }
}
