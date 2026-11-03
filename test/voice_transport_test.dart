import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

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
    });
  });

  group('live voice transport', () {
    test('voiceEvents carries only the voice events', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final seen = <String>[];
      final sub = c.voiceEvents.listen((e) => seen.add(e.name));

      realtime.emit('message', {'body': 'hi'});
      realtime.emit('voice_ready', {'inputRate': 16000});
      realtime.emit('typing', {});
      realtime.emit('voice_state', {'state': 'speaking'});
      realtime.emit('voice_audio', {'pcm': Uint8List.fromList([1, 2])});
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['voice_ready', 'voice_state', 'voice_audio']);
      await sub.cancel();
      c.dispose();
    });

    test('voiceStart sends who is signed in and what the app can show, so the agent can act for the customer', () async {
      final c = makeController(realtime: realtime, server: server);
      c.agent = KerabieAgentOptions(getUserToken: () async => 'tok-123', screens: {'open_screen': (args) async => 'opened'});
      await c.start();

      await c.voiceStart();

      expect(realtime.voiceStarts, hasLength(1));
      expect(realtime.voiceStarts.single, containsPair('userToken', 'tok-123'));
      expect(realtime.voiceStarts.single!['uiTools'], ['open_screen']);
      c.dispose();
    });

    test('voiceStart without an agent sends no agent details', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      await c.voiceStart();

      expect(realtime.voiceStarts, [null]);
      c.dispose();
    });

    test('the customer\'s speech and the stop go to the server', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      c.voiceAudio(Uint8List.fromList([1, 2, 3, 4]));
      c.voiceStop();

      expect(realtime.voiceChunks.single, [1, 2, 3, 4]);
      expect(realtime.voiceStops, 1);
      c.dispose();
    });
  });
}
