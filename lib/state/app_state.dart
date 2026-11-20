import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/hermes_http.dart';
import '../api/hermes_rpc.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
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

  /// Remembered password (secure storage); null when not kept.
  String? _password;

  /// Why the user landed on the login screen without asking to (e.g. the
  /// remembered password was rejected). Shown by the login form.
  String? authError;

  String? get savedPassword => _password;

  /// Language picked in settings ("cs", "en"); null follows the device.
  String? languageCode;

  static const _languageKey = 'language';

  HermesHttp? _http;
  HermesRpc? _rpc;
  StreamSubscription<ConnectionStatus>? _statusSub;
  Timer? _rosterTimer;

  List<Bot> bots = [];

  /// Bots the roster hides. They still belong to folders, so a folder rename
  /// has to reach them too.
  List<Bot> _hiddenBots = [];
  bool loadingBots = false;
  String? botsError;
  final Map<String, ChatController> _chats = {};

  // Local, per-device bookkeeping (like the dashboard's own storage).
  Map<String, int> _seen = {}; // bot name -> last seen activity (ms)
  Set<String> collapsed = {};

  /// Folder keys in the order the user dragged them into. Kept per device,
  /// like the dashboard keeps its own. Folders missing here go last, by name.
  List<String> sectionOrder = [];
  BotFilter filter = BotFilter.all;
  String query = '';
  String? openBot;

  static const _rosterEvery = Duration(seconds: 20);

  HermesRpc? get rpc => _rpc;
  ConnectionStatus get connection =>
      _rpc?.status ?? ConnectionStatus.disconnected;

  Future<void> init() async {
    await _loadLanguage();
    serverUrl = await _store.serverUrl();
    username = await _store.username();
    _password = await _store.password();
    await _loadLocal();
    final cookies = await _store.cookies();
    if (cookies.isEmpty) {
      if (await _store.autoLogin() && await _silentLogin()) return;
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
        if (await _silentLogin()) return;
        phase = AuthPhase.signedOut;
      } else {
        // Offline / server down: stay signed in, let the user retry.
        _enterSignedIn();
        botsError = describeError(e);
      }
      notifyListeners();
    }
  }

  /// Signs in with the remembered password, if any. Returns true when signed
  /// in; otherwise leaves the reason in [authError]. A rejected password is
  /// forgotten so it is not retried forever.
  Future<bool> _silentLogin() async {
    final password = _password;
    if (password == null || username.isEmpty) return false;
    try {
      await _passwordLogin(serverUrl, username, password);
      authError = null;
      await _loadLocal();
      _enterSignedIn();
      return true;
    } catch (e) {
      if (e is HermesHttpException && e.isUnauthorized) {
        _password = null;
        await _store.savePassword(null);
        authError = Strings.current.savedPasswordExpired;
      } else {
        authError = describeError(e);
      }
      return false;
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
    bool rememberPassword = true,
  }) async {
    await _passwordLogin(serverUrl, username, password);
    this.serverUrl = serverUrl;
    this.username = username;
    _password = rememberPassword ? password : null;
    authError = null;
    await _store.saveLogin(serverUrl: serverUrl, username: username);
    await _store.savePassword(_password);
    await _store.setAutoLogin(true);
    await _loadLocal();
    _enterSignedIn();
  }

  /// POSTs the password login on fresh clients; on success the session
  /// cookies are in the client (and persisted via [_setupClients]).
  Future<void> _passwordLogin(
    String serverUrl,
    String username,
    String password,
  ) async {
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
        throw HermesHttpException(500, Strings.current.errorNoSessionCookie);
      }
    } catch (e) {
      await _teardown(clearCookies: true);
      rethrow;
    }
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
    // Keep the password for the login form, but do not sign back in on our own.
    await _store.setAutoLogin(false);
    authError = null;
    phase = AuthPhase.signedOut;
    notifyListeners();
  }

  void _onSessionExpired() {
    if (phase != AuthPhase.signedIn) return;
    // Leave signedIn right away so concurrent 401s do not race us here.
    phase = AuthPhase.loading;
    notifyListeners();
    _teardown(clearCookies: true).then((_) async {
      botsError = null;
      if (await _silentLogin()) return;
      phase = AuthPhase.signedOut;
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
    _hiddenBots = [];
  }

  // --- roster --------------------------------------------------------------

  Future<List<Bot>> _fetchRoster() async {
    final all = await _fetchAllBots();
    _hiddenBots = all.where((b) => b.hidden).toList();
    return all.where((b) => !b.hidden).toList();
  }

  Future<List<Bot>> _fetchAllBots() async {
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
      .where((b) => b.name.isNotEmpty)
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
  List<BotSection> get sections => _sections(bots.where(_matchesFilter));

  List<BotSection> _sections(Iterable<Bot> members) {
    final byKey = <String, BotSection>{};
    for (final b in members) {
      final key = b.sectionId != null
          ? 'section:${b.sectionId}'
          : BotSection.unassignedKey;
      final title = b.sectionId != null
          ? (b.sectionName ?? Strings.current.folderFallback)
          : Strings.current.unassigned;
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
    int rank(BotSection s) {
      final i = sectionOrder.indexOf(s.key);
      return i < 0 ? sectionOrder.length : i;
    }

    final named =
        byKey.values.where((s) => s.key != BotSection.unassignedKey).toList()
          ..sort((a, b) {
            final byRank = rank(a).compareTo(rank(b));
            if (byRank != 0) return byRank;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
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

  /// Moves folder [key] in front of folder [before], or to the end of the
  /// folders when [before] is null. Works on every folder, also the ones the
  /// current search or filter hides.
  void moveSection(String key, {String? before}) {
    if (key == BotSection.unassignedKey || key == before) return;
    final order = [
      for (final s in _sections(bots))
        if (s.key != BotSection.unassignedKey && s.key != key) s.key,
    ];
    final at = before == null ? -1 : order.indexOf(before);
    order.insert(at < 0 ? order.length : at, key);
    sectionOrder = order;
    notifyListeners();
    unawaited(_saveLocal());
  }

  /// Renames folder [key] the way the dashboard does: the name lives in every
  /// member bot's profile metadata, so each member gets the new name.
  /// Throws when the server refuses a write.
  Future<void> renameSection(String key, String name) async {
    final title = name.trim();
    final rpc = _rpc;
    if (title.isEmpty || rpc == null || key == BotSection.unassignedKey) return;
    try {
      for (final b in [...bots, ..._hiddenBots]) {
        if ('section:${b.sectionId}' != key || b.sectionName == title) continue;
        if (!await _writeSectionName(rpc, b, title)) {
          // Someone else edited the bot meanwhile: reread it and retry once.
          final fresh = (await _fetchAllBots()).where((x) => x.name == b.name);
          if (fresh.isEmpty ||
              !await _writeSectionName(rpc, fresh.first, title)) {
            throw StateError(Strings.current.renameFolderFailed);
          }
        }
      }
    } finally {
      await refreshBots(silent: true);
    }
  }

  Future<bool> _writeSectionName(HermesRpc rpc, Bot b, String title) =>
      _writeMeta(rpc, b, {...b.meta, 'sectionName': title});

  /// Replaces the bot's whole `hermes-bots` block. False when the server
  /// refused it, e.g. because someone else edited the bot meanwhile.
  Future<bool> _writeMeta(
    HermesRpc rpc,
    Bot b,
    Map<String, dynamic> meta,
  ) async {
    final res = await rpc.request('profiles.configure', {
      'name': b.name,
      'ui_meta': {Bot.metaKey: meta},
      if (b.metaRevision != null)
        'ui_meta_expected_revisions': {Bot.metaKey: b.metaRevision},
    });
    final applied = res is Map ? res['applied'] : null;
    return applied is Map && applied['ui_meta'] == true;
  }

  // --- bot profile ---------------------------------------------------------

  /// The bot as the roster knows it now (hidden ones included).
  Bot? botNamed(String name) {
    for (final b in [...bots, ..._hiddenBots]) {
      if (b.name == name) return b;
    }
    return null;
  }

  HermesRpc get _connected {
    final rpc = _rpc;
    if (rpc == null) throw RpcException(-1, 'Not connected');
    return rpc;
  }

  /// The provider, model and SOUL.md the bot's profile is set to.
  Future<BotSetup> botSetup(Bot bot) async {
    final res = await _connected.requestWith('profiles.describe', {
      'name': bot.name,
    }, timeout: const Duration(seconds: 30));
    if (res is! Map) return const BotSetup();
    final model = res['model'];
    return BotSetup(
      provider: model is Map ? model['provider']?.toString().trim() ?? '' : '',
      model: model is Map ? model['default']?.toString().trim() ?? '' : '',
      soul: res['soul']?.toString() ?? '',
    );
  }

  /// Providers and their models a bot can be switched to.
  Future<List<ModelProvider>> modelProviders() async {
    final res = await _connected.requestWith('model.options', {
      'include_unconfigured': true,
      'explicit_only': false,
    }, timeout: const Duration(seconds: 30));
    final rows = res is Map ? res['providers'] : null;
    return (rows as List? ?? const [])
        .map(ModelProvider.fromJson)
        .nonNulls
        .toList();
  }

  /// Saves the bot's title and face. A null [shape] or [color] goes back to
  /// the one derived from the bot's name. Throws when the server refuses.
  Future<void> saveBotAppearance(
    Bot bot, {
    required String title,
    required String? shape,
    required String? color,
  }) async {
    final rpc = _connected;
    Map<String, dynamic> edited(Bot b) {
      final meta = {...b.meta};
      void put(String key, String? value) =>
          value == null ? meta.remove(key) : meta[key] = value;
      final faceChanged = shape != b.shape || color != b.color;
      put('title', title.trim().isEmpty ? null : title.trim());
      put('shape', shape);
      put('color', color);
      // The dashboard's mark for a face the user picked by hand.
      if (faceChanged) meta['custom'] = true;
      return meta;
    }

    if (await _writeMeta(rpc, bot, edited(bot))) return;
    // Someone else edited the bot meanwhile: reread it and retry once.
    final fresh = (await _fetchAllBots()).where((x) => x.name == bot.name);
    if (fresh.isEmpty ||
        !await _writeMeta(rpc, fresh.first, edited(fresh.first))) {
      throw StateError(Strings.current.botSaveRefused);
    }
  }

  /// Saves the bot's description (`hermes profile describe`).
  Future<void> saveBotDescription(Bot bot, String text) async {
    _checkCli(
      await _connected.requestWith('cli.exec', {
        'argv': ['profile', 'describe', bot.name, '--text', text.trim()],
      }, timeout: const Duration(seconds: 30)),
    );
  }

  /// Switches the bot to [provider] and [model]; both empty makes it inherit
  /// the launch profile's model again. Returns the server's question when it
  /// wants the switch confirmed (an expensive model): ask the user and call
  /// again with [confirmed].
  Future<String?> saveBotModel(
    Bot bot, {
    required String provider,
    required String model,
    bool confirmed = false,
  }) async {
    final rpc = _connected;
    if (provider.isEmpty && model.isEmpty) {
      _checkCli(
        await rpc.requestWith('cli.exec', {
          'argv': ['--profile', bot.name, 'config', 'unset', 'model'],
        }, timeout: const Duration(seconds: 30)),
      );
      return null;
    }
    final res = await rpc.requestWith('profiles.configure', {
      'name': bot.name,
      'model': model,
      'provider': provider,
      if (confirmed) 'confirm_expensive_model': true,
    }, timeout: const Duration(seconds: 30));
    if (res is Map && res['confirm_required'] == true && !confirmed) {
      return res['confirm_message']?.toString() ?? '';
    }
    final applied = res is Map ? res['applied'] : null;
    if (applied is! Map || applied['model'] != true) {
      throw StateError(Strings.current.botSaveRefused);
    }
    return null;
  }

  /// Replaces the bot's SOUL.md. Throws when the server refuses.
  Future<void> saveBotSoul(Bot bot, String soul) async {
    final res = await _connected.requestWith('profiles.configure', {
      'name': bot.name,
      'soul': soul.trim(),
    }, timeout: const Duration(seconds: 30));
    final applied = res is Map ? res['applied'] : null;
    if (applied is! Map || applied['soul'] != true) {
      throw StateError(Strings.current.botSaveRefused);
    }
  }

  static void _checkCli(Object? res) {
    if (res is! Map) return;
    final code = res['code'];
    if (res['blocked'] == true || (code is num && code != 0)) {
      final err = (res['stderr'] ?? res['error'] ?? '').toString().trim();
      throw StateError(err.isEmpty ? Strings.current.botSaveRefused : err);
    }
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

  // --- language ------------------------------------------------------------

  Future<void> _loadLanguage() async {
    try {
      final p = await SharedPreferences.getInstance();
      _applyLanguage(p.getString(_languageKey));
    } catch (_) {}
  }

  /// Switches the app language; null goes back to following the device.
  Future<void> setLanguage(String? code) async {
    if (code == languageCode) return;
    _applyLanguage(code);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (code == null) {
        await p.remove(_languageKey);
      } else {
        await p.setString(_languageKey, code);
      }
    } catch (_) {}
  }

  void _applyLanguage(String? code) {
    final known = Strings.supportedLocales.any((l) => l.languageCode == code);
    languageCode = known ? code : null;
    Strings.current = Strings.forLocale(
      languageCode != null
          ? Locale(languageCode!)
          : Strings.resolve(PlatformDispatcher.instance.locales),
    );
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
      sectionOrder = p.getStringList('$_localKey::sectionOrder') ?? [];
    } catch (_) {
      _seen = {};
      collapsed = {};
      sectionOrder = [];
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
      await p.setStringList('$_localKey::sectionOrder', sectionOrder);
    } catch (_) {}
  }

  static String describeError(Object e) {
    final s = Strings.current;
    if (e is HermesHttpException) {
      switch (e.statusCode) {
        case 401:
          return s.errorBadCredentials;
        case 404:
          return s.errorNoPasswordLogin;
        case 429:
          return s.errorTooManyAttempts;
        case 503:
          return s.errorServerDown;
      }
      return s.errorServer(e.message);
    }
    if (e is SocketException) return s.errorUnreachable(e.message);
    if (e is HandshakeException) return s.errorTls(e.message);
    if (e is TimeoutException) return s.errorTimeout;
    if (e is FormatException) return s.errorBadServerUrl;
    if (e is StateError) return e.message;
    if (e is RpcException) return e.message;
    return e.toString();
  }

  @override
  void dispose() {
    _teardown(clearCookies: false);
    super.dispose();
  }
}
