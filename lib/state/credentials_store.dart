import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the server URL + username (plain prefs) and the secrets — session
/// cookies and the remembered password — in secure storage. When the keychain
/// is unavailable (e.g. unsigned macOS debug builds without the
/// keychain-access-groups entitlement) secrets fall back to prefs so the app
/// still remembers the login.
class CredentialsStore {
  static const _kServer = 'server_url';
  static const _kUser = 'username';
  static const _kCookies = 'session_cookies';
  static const _kPassword = 'password';
  static const _kAutoLogin = 'auto_login';
  static const defaultServer = 'https://hermes.devrel.cz';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String> serverUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServer) ?? defaultServer;
  }

  Future<String> username() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUser) ?? '';
  }

  Future<void> saveLogin({
    required String serverUrl,
    required String username,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, serverUrl);
    await p.setString(_kUser, username);
  }

  /// The remembered password, or null when the user did not want it kept.
  Future<String?> password() async {
    final v = await _readSecret(_kPassword);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Stores [password]; null forgets it.
  Future<void> savePassword(String? password) =>
      _writeSecret(_kPassword, password);

  /// Whether the app may sign in on its own with the remembered password.
  /// Cleared by an explicit logout so the user stays signed out.
  Future<bool> autoLogin() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoLogin) ?? true;
  }

  Future<void> setAutoLogin(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoLogin, value);
  }

  Future<Map<String, String>> cookies() async {
    final raw = await _readSecret(_kCookies);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCookies(Map<String, String> cookies) =>
      _writeSecret(_kCookies, cookies.isEmpty ? null : jsonEncode(cookies));

  // --- secure storage with prefs fallback ----------------------------------

  Future<String?> _readSecret(String key) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null) return v;
    } catch (_) {
      // Keychain unavailable: use the prefs copy below.
    }
    // Also covers a value written to prefs while the keychain was failing.
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  Future<void> _writeSecret(String key, String? value) async {
    final p = await SharedPreferences.getInstance();
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
      // Keychain worked: drop any stale plain-text fallback copy.
      await p.remove(key);
    } catch (_) {
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, value);
      }
    }
  }
}
