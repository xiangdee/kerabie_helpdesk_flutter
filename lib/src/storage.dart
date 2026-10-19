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
}

/// `ks_` followed by random characters and the time, like the other Kerabie SDKs.
String generateSessionId() {
  final random = Random.secure().nextInt(1 << 32).toRadixString(36);
  return 'ks_$random${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
}
