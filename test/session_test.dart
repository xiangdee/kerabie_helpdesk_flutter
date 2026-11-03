import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/person.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

KerabieConfig configFor(KerabieUser? user) => KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', user: user);

/// What the app had saved on the phone from an earlier run: a session, and who it was kept for.
Map<String, Object> saved(String sessionId, {String? person}) => {
      'kerabie:sdk:session_id': jsonEncode({'value': sessionId, 'ts': DateTime.now().millisecondsSinceEpoch}),
      if (person != null) 'kerabie:sdk:session_person': jsonEncode(person),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime realtime;
  late FakeServer server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realtime = FakeRealtime();
    server = FakeServer({
      'GET /public/widget/init': {'orgId': 42, 'settings': {}},
      'GET /public/widget/messages': {'conversationId': null, 'messages': []},
      'GET /public/widget/conversations': {'conversations': []},
      // Like the real server for the same person: the session sent is the session to use.
      'POST /public/widget/identify': (http.Request r) => http.Response(jsonEncode({'success': true, 'sessionId': r.headers['x-session-id']}), 200),
      'POST /public/widget/push-token': {'success': true},
      'DELETE /public/widget/push-token': {'success': true},
    });
  });

  group('a session belongs to one person', () {
    test('kerabieSessionIsOthers: a person\'s session is theirs only, an anonymous one can be taken', () {
      expect(kerabieSessionIsOthers('id:42', 'id:43'), isTrue);
      expect(kerabieSessionIsOthers('id:42', ''), isTrue);
      expect(kerabieSessionIsOthers('id:42', 'id:42'), isFalse);
      expect(kerabieSessionIsOthers('', 'id:42'), isFalse);
      expect(kerabieSessionIsOthers(null, 'id:42'), isFalse);
    });

    test('the session the server names for the person is the one used, and the old one stops pushing', () async {
      server.routes['POST /public/widget/identify'] = {'success': true, 'sessionId': 'ks_for_b'};
      final c = makeController(realtime: realtime, server: server, config: configFor(const KerabieUser(id: 'b', name: 'Ben')));

      await c.start();

      expect(c.sessionId, 'ks_for_b');
      expect(realtime.connectArgs, containsPair('sessionId', 'ks_for_b'));
      expect(server.last('DELETE', '/public/widget/push-token')!.headers['x-session-id'], 'ks_fixed');
      // Nothing was loaded on the old session before the switch.
      final history = server.requests.where((r) => r.url.path == '/public/widget/messages').toList();
      expect(history.every((r) => r.headers['x-session-id'] == 'ks_for_b'), isTrue);
      c.dispose();
    });

    test('the same person keeps their session', () async {
      final c = makeController(realtime: realtime, server: server, config: configFor(const KerabieUser(id: 'a')));

      await c.start();

      expect(c.sessionId, 'ks_fixed');
      expect(server.last('DELETE', '/public/widget/push-token'), isNull);
      c.dispose();
    });

    test('a session saved for someone else is dropped when the app starts for another person, before anything loads', () async {
      SharedPreferences.setMockInitialValues(saved('ks_of_a', person: 'id:a'));
      final c = makeController(
        realtime: realtime,
        server: server,
        generateSession: () => 'ks_new',
        config: configFor(const KerabieUser(id: 'b')),
      );

      await c.start();

      expect(c.sessionId, 'ks_new');
      expect(server.last('DELETE', '/public/widget/push-token')!.headers['x-session-id'], 'ks_of_a');
      expect(server.requests.where((r) => r.url.path == '/public/widget/messages').every((r) => r.headers['x-session-id'] == 'ks_new'), isTrue);
      c.dispose();
    });

    test('a session saved for a person is dropped when the app starts with nobody signed in', () async {
      SharedPreferences.setMockInitialValues(saved('ks_of_a', person: 'id:a'));
      final c = makeController(realtime: realtime, server: server, generateSession: () => 'ks_new');

      await c.start();

      expect(c.sessionId, 'ks_new');
      c.dispose();
    });

    test('an anonymous session is kept when someone signs in', () async {
      SharedPreferences.setMockInitialValues(saved('ks_anon'));
      final c = makeController(realtime: realtime, server: server, config: configFor(const KerabieUser(id: 'a')));

      await c.start();

      expect(c.sessionId, 'ks_anon');
      expect(server.last('DELETE', '/public/widget/push-token'), isNull);
      c.dispose();
    });

    test('logout drops the session, stops its notifications and gives the phone\'s token to the new one', () async {
      var n = 0;
      final c = makeController(
        realtime: realtime,
        server: server,
        generateSession: () => 'ks_${++n}',
        config: configFor(const KerabieUser(id: 'a')),
      );
      await c.start();
      await c.registerPushToken('tok', provider: KerabiePushProvider.expo);

      await c.logout();

      expect(c.currentUser, isNull);
      expect(c.sessionId, 'ks_2');
      expect(realtime.connectArgs, containsPair('sessionId', 'ks_2'));
      expect(server.last('DELETE', '/public/widget/push-token')!.headers['x-session-id'], 'ks_1');
      await Future<void>.delayed(Duration.zero);
      expect(server.last('POST', '/public/widget/push-token')!.headers['x-session-id'], 'ks_2');
      c.dispose();
    });

    test('a person signing in after logout starts clean on the new session', () async {
      var n = 0;
      final c = makeController(realtime: realtime, server: server, generateSession: () => 'ks_${++n}', config: configFor(const KerabieUser(id: 'a')));
      await c.start();
      await c.logout();

      await c.setUser(const KerabieUser(id: 'b', name: 'Ben'));

      expect(c.sessionId, 'ks_2');
      expect(c.currentUser!.id, 'b');
      c.dispose();
    });
  });
}
