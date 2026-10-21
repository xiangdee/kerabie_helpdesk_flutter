import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the visitor's session id so a returning visitor sees the same conversation.
/// Keeps the visitor's session for 7 days so the same customer sees their conversation again.
class KerabieStorage {
  KerabieStorage({DateTime Function()? now, String Function()? generate})
      : _now = now ?? DateTime.now,
        _generate = generate ?? generateSessionId;

  static const _key = 'kerabie:sdk:session_id';
  static const _ttl = Duration(days: 7);

  final DateTime Function() _now;
  final String Function() _generate;

  /// The saved session id, or a new one when there is none or it has expired.
  Future<String> sessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        final saved = DateTime.fromMillisecondsSinceEpoch((entry['ts'] as num).toInt());
        if (_now().difference(saved) <= _ttl && entry['value'] is String) return entry['value'] as String;
      } catch (_) {
        // A damaged entry is replaced below.
      }
    }
    final fresh = _generate();
    await prefs.setString(_key, jsonEncode({'value': fresh, 'ts': _now().millisecondsSinceEpoch}));
    return fresh;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// A remembered value, or null when there is none or it is older than seven days.
  Future<T?> read<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('kerabie:sdk:$key');
    if (raw == null) return null;
    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final saved = DateTime.fromMillisecondsSinceEpoch((entry['ts'] as num).toInt());
      if (_now().difference(saved) > _ttl) {
        await prefs.remove('kerabie:sdk:$key');
        return null;
      }
      final value = entry['value'];
      return value is T ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Remembers a JSON value for seven days.
  Future<void> write(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kerabie:sdk:$key', jsonEncode({'value': value, 'ts': _now().millisecondsSinceEpoch}));
  }

  /// Like [read], but without an expiry. For things that must not reset, such as "this campaign was already shown".
  Future<T?> readForever<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('kerabie:sdk:$key');
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is T ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeForever(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kerabie:sdk:$key', jsonEncode(value));
  }
}

/// `ks_` followed by random characters and the time, like the other Kerabie SDKs.
String generateSessionId() {
  final random = Random.secure().nextInt(1 << 32).toRadixString(36);
  return 'ks_$random${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
}
