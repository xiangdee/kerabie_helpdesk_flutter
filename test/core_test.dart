// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/api_client.dart';
import 'package:kerabie_helpdesk_flutter/src/config.dart' show parseHexColor;
import 'package:kerabie_helpdesk_flutter/src/storage.dart';import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KerabieMessage.fromServer', () {
    test('maps the server roles to senders', () {
      expect(KerabieMessage.fromServer({'id': 1, 'body': 'a', 'senderRole': 'customer'}).sender, KerabieSender.visitor);
      expect(KerabieMessage.fromServer({'id': 2, 'body': 'b', 'senderRole': 'agent'}).sender, KerabieSender.agent);
      expect(
        KerabieMessage.fromServer({'id': 3, 'body': 'c', 'senderRole': 'agent', 'metadata': {'source': 'ai'}}).sender,
        KerabieSender.bot,
      );
    });

    test('turns numeric ids into strings and survives missing fields', () {
      final m = KerabieMessage.fromServer({'id': 12, 'conversationId': 4});
      expect(m.id, '12');
      expect(m.conversationId, 4);
      expect(m.body, '');
      expect(m.type, 'text');
    });
  });

  group('KerabieUser.toJson', () {
    test('leaves out what was not set', () {
      expect(const KerabieUser(name: 'Jane').toJson(), {'name': 'Jane'});
      expect(
        const KerabieUser(id: 'u1', email: 'j@x.co', phone: '+1', customAttributes: {'plan': 'pro'}).toJson(),
        {'id': 'u1', 'email': 'j@x.co', 'phone': '+1', 'customAttributes': {'plan': 'pro'}},
      );
    });
  });

  group('KerabieSettings.fromServer', () {
    test('reads colours, shape and text from the dashboard settings', () {
      final s = KerabieSettings.fromServer({
        'name': 'Acme',
        'primaryColor': '#2f5f49',
        'secondaryColor': '0f766e',
        'colorType': 'singleColor',
        'borderRadius': 'small',
        'showBranding': false,
      });
      expect(s.chat.name, 'Acme');
      expect(s.primaryColor, const Color(0xFF2F5F49));
      expect(s.secondaryColor, const Color(0xFF0F766E));
      expect(s.gradient, isFalse);
      expect(s.cornerRadius, 8);
      expect(s.chat.showBranding, isFalse);
    });

    test('reads the custom launcher icon, its size and the chatbot avatar, and ignores blanks', () {
      final s = KerabieSettings.fromServer({
        'launcherIconUrl': ' https://cdn.example.com/icon.png ',
        'launcherIconSize': 32,
        'chatbotAvatarUrl': 'https://cdn.example.com/bot.png',
      });
      expect(s.launcherIconUrl, 'https://cdn.example.com/icon.png');
      expect(s.launcherIconSize, 32.0);
      expect(s.chatbotAvatarUrl, 'https://cdn.example.com/bot.png');

      final blank = KerabieSettings.fromServer({'launcherIconUrl': '  ', 'launcherIconSize': null, 'chatbotAvatarUrl': null});
      expect(blank.launcherIconUrl, isNull);
      expect(blank.launcherIconSize, isNull);
      expect(blank.chatbotAvatarUrl, isNull);
    });

    test('defaults when the server says nothing', () {
      final s = KerabieSettings.fromServer({});
      expect(s.gradient, isTrue);
      expect(s.chat.showBranding, isNull);
      expect(s.chat.chatbotEnabled, isNull);
      expect(s.cornerRadius, isNull);
    });
  });

  group('KerabiePalette.contrastText', () {
    test('picks dark text on light brand colours and white on dark ones', () {
      expect(KerabiePalette.contrastText(const Color(0xFFFFFFFF)), const Color(0xFF0F172A));
      expect(KerabiePalette.contrastText(const Color(0xFFA3E635)), const Color(0xFF0F172A)); // lime
      expect(KerabiePalette.contrastText(const Color(0xFF334155)), const Color(0xFFFFFFFF)); // default slate
      expect(KerabiePalette.contrastText(const Color(0xFF000000)), const Color(0xFFFFFFFF));
    });
  });

  group('parseHexColor', () {
    test('accepts short, long and alpha forms and rejects junk', () {
      expect(parseHexColor('#fff'), const Color(0xFFFFFFFF));
      expect(parseHexColor('#102030'), const Color(0xFF102030));
      expect(parseHexColor('80102030'), const Color(0x80102030));
      expect(parseHexColor('nope'), isNull);
      expect(parseHexColor(null), isNull);
      expect(parseHexColor('#12'), isNull);
    });
  });

  group('KerabieStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps the same session id between launches', () async {
      var n = 0;
      final storage = KerabieStorage(generate: () => 'ks_${++n}');
      expect(await storage.sessionId(), 'ks_1');
      expect(await storage.sessionId(), 'ks_1');
    });

    test('starts a new session after seven days', () async {
      var now = DateTime(2026, 10, 1);
      var n = 0;
      final storage = KerabieStorage(now: () => now, generate: () => 'ks_${++n}');
      expect(await storage.sessionId(), 'ks_1');

      now = now.add(const Duration(days: 6, hours: 23));
      expect(await storage.sessionId(), 'ks_1');
      now = now.add(const Duration(days: 2));
      expect(await storage.sessionId(), 'ks_2');
    });

    test('replaces a damaged entry', () async {
      SharedPreferences.setMockInitialValues({'kerabie:sdk:session_id': 'not json'});
      final storage = KerabieStorage(generate: () => 'ks_fresh');
      expect(await storage.sessionId(), 'ks_fresh');
    });

    test('uses a stable key and shape', () async {
      final storage = KerabieStorage(generate: () => 'ks_abc');
      await storage.sessionId();
      final raw = (await SharedPreferences.getInstance()).getString('kerabie:sdk:session_id')!;
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      expect(entry['value'], 'ks_abc');
      expect(entry['ts'], isA<int>());
    });

    test('generated ids start with ks_ and differ', () {
      expect(generateSessionId(), startsWith('ks_'));
      expect(generateSessionId(), isNot(generateSessionId()));
    });
  });

  group('KerabieApi', () {
    test('sends json with the identifying headers', () async {
      late http.Request seen;
      final api = KerabieApi(
        baseUrl: 'https://api.example.com',
        widgetKey: 'wk_1',
        sessionId: 'ks_1',
        client: MockClient((req) async {
          seen = req;
          return http.Response('{"success":true}', 200);
        }),
      );
      final res = await api.post('/public/widget/identify', {'user': {'name': 'Jane'}});

      expect(res['success'], true);
      expect(seen.url.toString(), 'https://api.example.com/public/widget/identify');
      expect(seen.headers['x-widget-key'], 'wk_1');
      expect(seen.headers['x-session-id'], 'ks_1');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {'user': {'name': 'Jane'}});
    });

    test('turns an error response into an exception with the server message', () async {
      final api = KerabieApi(
        baseUrl: 'https://api.example.com',
        widgetKey: 'k',
        sessionId: 's',
        client: MockClient((_) async => http.Response('{"message":"Invalid widget key"}', 401)),
      );
      await expectLater(
        api.get('/public/widget/init'),
        throwsA(isA<KerabieException>().having((e) => e.status, 'status', 401).having((e) => e.message, 'message', 'Invalid widget key')),
      );
    });

    test('wraps a network failure', () async {
      final api = KerabieApi(
        baseUrl: 'https://api.example.com',
        widgetKey: 'k',
        sessionId: 's',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(api.get('/x'), throwsA(isA<KerabieException>().having((e) => e.status, 'status', isNull)));
    });

    test('passes query parameters', () async {
      late Uri seen;
      final api = KerabieApi(
        baseUrl: 'https://api.example.com',
        widgetKey: 'k',
        sessionId: 's',
        client: MockClient((req) async {
          seen = req.url;
          return http.Response('{}', 200);
        }),
      );
      await api.get('/public/knowledge-base', query: {'q': 'refund'});
      expect(seen.queryParameters, {'q': 'refund'});
    });
  });
}
