import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the server URL + username (plain prefs) and the session cookies
/// (secure storage; falls back to prefs if the keychain is unavailable, e.g.
/// unsigned macOS debug builds).
class CredentialsStore {
  static const _kServer = 'server_url';
  static const _kUser = 'username';
  static const _kCookies = 'session_cookies';
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

  Future<Map<String, String>> cookies() async {
    String? raw;
    try {
      raw = await _secure.read(key: _kCookies);
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      raw = p.getString(_kCookies);
    }
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    final raw = jsonEncode(cookies);
    try {
      if (cookies.isEmpty) {
        await _secure.delete(key: _kCookies);
      } else {
        await _secure.write(key: _kCookies, value: raw);
      }
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      if (cookies.isEmpty) {
        await p.remove(_kCookies);
      } else {
        await p.setString(_kCookies, raw);
      }
    }
  }
}
