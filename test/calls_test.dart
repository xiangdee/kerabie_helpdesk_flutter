// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

Map<String, dynamic> callJson({String status = 'RINGING', bool video = false, String? handler, int? position}) => {
      'callId': 31,
      'status': status,
      'video': video,
      'handler': handler,
      if (position != null) 'queuePosition': position,
      'livekit': {'url': 'wss://lk.test', 'token': 'jwt-token'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime realtime;

  FakeServer serverWith({bool calls = true, bool video = true, Map<String, Object> extra = const {}}) => FakeServer({
        'GET /public/widget/init': {
          'orgId': 42,
          'settings': {'callsEnabled': calls, 'videoCallsEnabled': video},
        },
        'GET /public/widget/messages': {'conversationId': null, 'messages': []},
        ...extra,
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    realtime = FakeRealtime();
  });
  tearDown(() => realtime.dispose());

  group('settings', () {
    test('read whether calls and video are on', () {
      final on = KerabieSettings.fromServer({'callsEnabled': true, 'videoCallsEnabled': true});
      expect(on.callsEnabled, isTrue);
      expect(on.videoCallsEnabled, isTrue);
    });

    test('default to off when the server says nothing or something else', () {
      expect(KerabieSettings.fromServer({}).callsEnabled, isFalse);
      expect(KerabieSettings.fromServer({'callsEnabled': 'yes', 'videoCallsEnabled': 1}).callsEnabled, isFalse);
      expect(KerabieSettings.fromServer({'callsEnabled': 'yes', 'videoCallsEnabled': 1}).videoCallsEnabled, isFalse);
    });
  });

  group('KerabieCallJoin', () {
    test('reads the call and the pass to join its room', () {
      final join = KerabieCallJoin.fromServer(callJson(status: 'QUEUED', position: 2));
      expect(join.callId, 31);
      expect(join.status, 'QUEUED');
      expect(join.queuePosition, 2);
      expect(join.handler, isNull);
      expect(join.livekitUrl, 'wss://lk.test');
      expect(join.livekitToken, 'jwt-token');
    });

    test('keeps who answered', () {
      expect(KerabieCallJoin.fromServer(callJson(status: 'ACTIVE', handler: 'AI')).handler, 'AI');
    });

    test('survives a response without the pass', () {
      final join = KerabieCallJoin.fromServer({'callId': 5});
      expect(join.livekitToken, '');
      expect(join.status, 'QUEUED');
    });
  });

  group('startCall', () {
    test('asks the server for a call and returns what the app needs to join', () async {
      final server = serverWith(extra: {'POST /public/widget/calls': callJson()});
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      final join = await c.startCall();
      expect(join.callId, 31);
      expect(join.livekitToken, 'jwt-token');
      final request = server.last('POST', '/public/widget/calls')!;
      expect(jsonDecode(request.body), {'video': false});
      c.dispose();
    });

    test('asks for video only when the dashboard allows it', () async {
      final allowed = serverWith(extra: {'POST /public/widget/calls': callJson(video: true)});
      final a = makeController(realtime: realtime, server: allowed);
      await a.start();
      await a.startCall(video: true);
      expect(jsonDecode(allowed.last('POST', '/public/widget/calls')!.body), {'video': true});
      a.dispose();

      final refused = serverWith(video: false, extra: {'POST /public/widget/calls': callJson()});
      final b = makeController(realtime: FakeRealtime(), server: refused);
      await b.start();
      await b.startCall(video: true);
      expect(jsonDecode(refused.last('POST', '/public/widget/calls')!.body), {'video': false});
      b.dispose();
    });

    test('throws the server\'s message when the call is refused', () async {
      final c = makeController(realtime: realtime, server: serverWith());
      await c.start();
      // The fake server answers 404 for a route it does not know.
      await expectLater(c.startCall(), throwsA(isA<KerabieException>()));
      c.dispose();
    });

    test('throws before the chat has started', () async {
      final c = makeController(realtime: realtime, server: serverWith());
      await expectLater(c.startCall(), throwsA(isA<KerabieException>()));
      c.dispose();
    });
  });

  group('currentCall and endCall', () {
    test('returns the call the visitor is still in, or null', () async {
      final server = serverWith(extra: {'GET /public/widget/calls/current': {'call': callJson(status: 'ACTIVE', handler: 'HUMAN')}});
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      expect((await c.currentCall())?.handler, 'HUMAN');
      c.dispose();

      final none = serverWith(extra: {'GET /public/widget/calls/current': {'call': null}});
      final d = makeController(realtime: FakeRealtime(), server: none);
      await d.start();
      expect(await d.currentCall(), isNull);
      d.dispose();
    });

    test('hangs up by call id', () async {
      final server = serverWith(extra: {'POST /public/widget/calls/31/end': {'success': true}});
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      await c.endCall(31);
      expect(server.last('POST', '/public/widget/calls/31/end'), isNotNull);
      c.dispose();
    });
  });

  group('callEvents', () {
    test('turn the server\'s call events into named events with the call id', () async {
      final c = makeController(realtime: realtime, server: serverWith());
      await c.start();
      final seen = <KerabieCallEvent>[];
      final sub = c.callEvents.listen(seen.add);

      realtime.emit('call_ringing', {'callId': 31});
      realtime.emit('call_queued', {'callId': 31, 'position': 2});
      realtime.emit('call_accepted', {'callId': 31, 'handler': 'AI'});
      realtime.emit('call_ended', {'callId': 31, 'reason': 'hangup'});
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((e) => e.name), ['ringing', 'queued', 'accepted', 'ended']);
      expect(seen.every((e) => e.callId == 31), isTrue);
      expect(seen[1].data['position'], 2);
      expect(seen[3].data['reason'], 'hangup');
      await sub.cancel();
      c.dispose();
    });

    test('do not disturb the chat', () async {
      final c = makeController(realtime: realtime, server: serverWith());
      await c.start();
      var rebuilds = 0;
      c.addListener(() => rebuilds++);
      realtime.emit('call_ringing', {'callId': 31});
      realtime.emit('call_ended', {'callId': 31, 'reason': 'missed'});
      expect(rebuilds, 0);
      expect(c.messages, isEmpty);
      c.dispose();
    });
  });
}
