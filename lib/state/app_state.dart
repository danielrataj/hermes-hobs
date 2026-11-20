import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/hermes_http.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import 'chat_controller.dart';
import 'credentials_store.dart';

enum AuthPhase { loading, signedOut, signedIn }

enum BotFilter { all, unread, pinned, active, recent, older }

/// One collapsible folder of the bot list.
class BotSection {
  BotSection({required this.key, required this.title, required this.bots});

  /// `section:<id>` or [unassignedKey].
  final String key;
  final String title;
  final List<Bot> bots;

  static const unassignedKey = 'section:unassigned';
}

/// App-wide state: login, the bot roster (Hermes profiles with their Bot Chat
/// summaries), local unread/collapse bookkeeping, and one live
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
  Timer? _rosterTimer;

  List<Bot> bots = [];
  bool loadingBots = false;
  String? botsError;
  final Map<String, ChatController> _chats = {};

  // Local, per-device bookkeeping (like the dashboard's own storage).
  Map<String, int> _seen = {}; // bot name -> last seen activity (ms)
  Set<String> collapsed = {};
  BotFilter filter = BotFilter.all;
  String query = '';
  String? openBot;

  static const _rosterEvery = Duration(seconds: 20);

  HermesRpc? get rpc => _rpc;
  ConnectionStatus get connection =>
      _rpc?.status ?? ConnectionStatus.disconnected;

  Future<void> init() async {
    serverUrl = await _store.serverUrl();
    username = await _store.username();
    await _loadLocal();
    final cookies = await _store.cookies();
    if (cookies.isEmpty) {
      phase = AuthPhase.signedOut;
      notifyListeners();
      return;
    }
    _setupClients(Uri.parse(serverUrl), cookies);
    try {
      await _http!.getJson('/api/auth/me');
      _enterSignedIn();
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        await _teardown(clearCookies: true);
        phase = AuthPhase.signedOut;
      } else {
        // Offline / server down: stay signed in, let the user retry.
        _enterSignedIn();
        botsError = describeError(e);
      }
      notifyListeners();
    }
  }

  void _setupClients(Uri base, Map<String, String> cookies) {
    final http = HermesHttp(baseUrl: base, cookies: cookies);
    http.onCookiesChanged = (c) => _store.saveCookies(c);
    final rpc = HermesRpc(http)..onUnauthorized = _onSessionExpired;
    _statusSub = rpc.statusStream.listen((s) {
      if (s == ConnectionStatus.connected) unawaited(refreshBots(silent: true));
      notifyListeners();
    });
    _http = http;
    _rpc = rpc;
  }

  void _enterSignedIn() {
    phase = AuthPhase.signedIn;
    notifyListeners();
    _rpc!.connect().catchError((_) {});
    unawaited(refreshBots());
    _rosterTimer?.cancel();
    _rosterTimer = Timer.periodic(_rosterEvery, (_) {
      if (connection == ConnectionStatus.connected) {
        unawaited(refreshBots(silent: true));
      }
    });
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await _teardown(clearCookies: true);
    _setupClients(Uri.parse(serverUrl), {});
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
    await _loadLocal();
    _enterSignedIn();
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
    _rosterTimer?.cancel();
    _rosterTimer = null;
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

  // --- roster --------------------------------------------------------------

  Future<List<Bot>> _fetchRoster() async {
    final rpc = _rpc;
    if (rpc != null) {
      try {
        await rpc.connect();
        final res = await rpc.requestWith('profiles.list', {
          'include_sessions': true,
        }, timeout: const Duration(seconds: 30)) as Map;
        return _parseRoster(res['profiles']);
      } on HermesHttpException {
        rethrow;
      } catch (_) {
        // Socket not ready: fall back to REST (no Bot Chat previews there).
      }
    }
    final res = await _http!.getJson('/api/profiles') as Map;
    return _parseRoster(res['profiles']);
  }

  static List<Bot> _parseRoster(Object? rows) => (rows as List? ?? const [])
      .whereType<Map>()
      .map((m) => Bot.fromJson(Map<String, dynamic>.from(m)))
      .where((b) => b.name.isNotEmpty && !b.hidden)
      .toList();

  Future<void> refreshBots({bool silent = false}) async {
    if (_http == null) return;
    if (loadingBots) return;
    loadingBots = true;
    if (!silent) {
      botsError = null;
      notifyListeners();
    }
    try {
      final list = await _fetchRoster();
      bots = list;
      botsError = null;
      for (final b in list) {
        _chats[b.name]?.updateBot(b);
      }
      // First sight of a bot: everything already there counts as read.
      var seededSeen = false;
      for (final b in list) {
        if (!_seen.containsKey(b.name)) {
          _seen[b.name] = b.lastActive?.millisecondsSinceEpoch ?? 0;
          seededSeen = true;
        }
      }
      if (seededSeen) unawaited(_saveSeen());
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        loadingBots = false;
        _onSessionExpired();
        return;
      }
      if (!silent || bots.isEmpty) botsError = describeError(e);
    } finally {
      loadingBots = false;
      notifyListeners();
    }
  }

  Future<SessionSummary?> _findCanonical(String profile) async {
    try {
      final list = await _fetchRoster();
      bots = list;
      notifyListeners();
      for (final b in list) {
        if (b.name == profile) return b.canonical;
      }
    } catch (_) {}
    return null;
  }

  // --- derived views -------------------------------------------------------

  bool isUnread(Bot b) {
    if (b.name == openBot) return false;
    final last = b.canonical?.lastActive;
    if (last == null) return false;
    return last.millisecondsSinceEpoch > (_seen[b.name] ?? 0) + 1000;
  }

  bool isWorking(Bot b) => b.workingNow || (_chats[b.name]?.busy ?? false);

  bool _matchesFilter(Bot b) {
    final last = b.lastActive;
    final age = last == null ? null : DateTime.now().difference(last);
    switch (filter) {
      case BotFilter.all:
        break;
      case BotFilter.unread:
        if (!isUnread(b)) return false;
      case BotFilter.pinned:
        if (!b.pinned) return false;
      case BotFilter.active:
        if (!(isWorking(b) ||
            (age != null && age < const Duration(minutes: 15)))) {
          return false;
        }
      case BotFilter.recent:
        if (age == null || age > const Duration(days: 1)) return false;
      case BotFilter.older:
        if (age != null && age <= const Duration(days: 1)) return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return b.displayName.toLowerCase().contains(q) ||
        b.name.toLowerCase().contains(q) ||
        b.description.toLowerCase().contains(q);
  }

  /// Bots grouped into the user's folders (`ui_meta.sectionId/sectionName`),
  /// "Nezařazení" last. Inside a folder: pinned first, then newest activity.
  List<BotSection> get sections {
    final byKey = <String, BotSection>{};
    for (final b in bots.where(_matchesFilter)) {
      final key = b.sectionId != null
          ? 'section:${b.sectionId}'
          : BotSection.unassignedKey;
      final title = b.sectionId != null
          ? (b.sectionName ?? 'Složka')
          : 'Nezařazení';
      byKey
          .putIfAbsent(key, () => BotSection(key: key, title: title, bots: []))
          .bots
          .add(b);
    }
    int byActivity(Bot a, Bot b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final ta = a.lastActive?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastActive?.millisecondsSinceEpoch ?? 0;
      if (ta != tb) return tb.compareTo(ta);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    }

    for (final s in byKey.values) {
      s.bots.sort(byActivity);
    }
    final named =
        byKey.values.where((s) => s.key != BotSection.unassignedKey).toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final rest = byKey[BotSection.unassignedKey];
    return [...named, ?rest];
  }

  /// True when the server has no user folders at all: draw a flat list.
  bool get hasFolders => bots.any((b) => b.sectionId != null);

  void setFilter(BotFilter f) {
    filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void toggleSection(String key) {
    if (!collapsed.remove(key)) collapsed.add(key);
    notifyListeners();
    unawaited(_saveLocal());
  }

  // --- chats ---------------------------------------------------------------

  /// Returns the live chat for [bot], creating and opening it on first use.
  ChatController chatFor(Bot bot) {
    final existing = _chats[bot.name];
    if (existing != null) return existing;
    final c = ChatController(
      rpc: _rpc!,
      bot: bot,
      findCanonical: _findCanonical,
      onTurnSettled: (b) {
        if (openBot == b.name) markSeen(b.name);
        unawaited(refreshBots(silent: true));
      },
    );
    _chats[bot.name] = c;
    unawaited(c.start());
    return c;
  }

  void setOpenBot(String? name) {
    final prev = openBot;
    openBot = name;
    if (name != null) markSeen(name);
    if (prev != null && prev != name) markSeen(prev);
    Future.microtask(notifyListeners);
  }

  void markSeen(String name) {
    _seen[name] = DateTime.now().millisecondsSinceEpoch;
    unawaited(_saveSeen());
  }

  Future<List<CronJob>> cronJobs(Bot bot) async {
    final rpc = _rpc;
    if (rpc == null) return [];
    await rpc.connect();
    final res = await rpc.requestWith('cron.manage', {
      'action': 'list',
      'profile': bot.name,
      'include_disabled': true,
    }, timeout: const Duration(seconds: 30));
    if (res is! Map) return [];
    if (res['success'] == false && res['error'] != null) {
      throw Exception(res['error'].toString());
    }
    final jobs = res['jobs'];
    if (jobs is! List) return [];
    return jobs
        .whereType<Map>()
        .map((j) => CronJob.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  void onAppResumed() {
    _rpc?.reconnectNow();
    if (phase == AuthPhase.signedIn) unawaited(refreshBots(silent: true));
  }

  // --- local persistence ---------------------------------------------------

  String get _localKey => 'local::$serverUrl::$username';

  Future<void> _loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final seen = p.getString('$_localKey::seen');
      _seen = seen == null
          ? {}
          : Map<String, int>.from(jsonDecode(seen) as Map);
      collapsed = (p.getStringList('$_localKey::collapsed') ?? const [])
          .toSet();
    } catch (_) {
      _seen = {};
      collapsed = {};
    }
  }

  Future<void> _saveSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_localKey::seen', jsonEncode(_seen));
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('$_localKey::collapsed', collapsed.toList());
    } catch (_) {}
  }

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
