
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
      'GET /public/widget/init': {
        'orgId': 42,
        'settings': {
          'name': 'Acme Support',
          'welcomeMessage': 'Hi, how can we help?',
          'primaryColor': '#2f5f49',
          'secondaryColor': '#0f766e',
          'colorType': 'gradient',
          'borderRadius': 'large',
        },
      },
      'GET /public/widget/messages': {
        'conversationId': 7,
        'messages': [
          serverMessage(1, 'Hello', role: 'customer'),
          serverMessage(2, 'Hi, how can we help?'),
        ],
      },
      'POST /public/widget/identify': {'success': true},
      'POST /public/widget/push-token': {'success': true},
    });
  });

  tearDown(() => realtime.dispose());

  group('start', () {
    test('loads history and dashboard settings, then connects with the organisation id', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      expect(c.messages.map((m) => m.body), ['Hello', 'Hi, how can we help?']);
      expect(c.messages.first.sender, KerabieSender.visitor);
      expect(c.messages.last.sender, KerabieSender.agent);
      expect(c.conversationId, 7);
      expect(c.settings.name, 'Acme Support');
      expect(c.settings.cornerRadius, 24);
      expect(realtime.connectArgs, containsPair('orgId', 42));
      expect(realtime.connectArgs, containsPair('sessionId', 'ks_fixed'));
      expect(realtime.connectArgs, containsPair('appName', 'Test app'));
      c.dispose();
    });

    test('sends the widget key and session id on every request', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      final init = server.last('GET', '/public/widget/init')!;
      expect(init.headers['x-widget-key'], 'wk_test');
      expect(init.headers['x-session-id'], 'ks_fixed');
      c.dispose();
    });

    test('still connects when the settings cannot be loaded', () async {
      final broken = FakeServer({});
      final c = makeController(realtime: realtime, server: broken);
      await c.start();

      expect(realtime.connectArgs, containsPair('orgId', 0));
      expect(c.messages, isEmpty);
      c.dispose();
    });

    test('identifies the user when the config has one', () async {
      final c = makeController(
        realtime: realtime,
        server: server,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'Test app',
          appVersion: '1.2.3',
          user: KerabieUser(name: 'Jane', email: 'jane@example.com', customAttributes: {'plan': 'pro'}),
        ),
      );
      await c.start();
      await Future<void>.delayed(Duration.zero);

      final identify = server.last('POST', '/public/widget/identify')!;
      expect(identify.body, contains('"name":"Jane"'));
      expect(identify.body, contains('"plan":"pro"'));
      expect(realtime.connectArgs, containsPair('user', 'Jane'));
      c.dispose();
    });

    test('starting twice connects once', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      realtime.connectArgs = null;
      await c.start();

      expect(realtime.connectArgs, isNull);
      c.dispose();
    });
  });

  group('sending', () {
    test('shows the message at once, then replaces it with the server copy', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      await c.sendMessage('Where is my order?');
      expect(c.messages.last.status, KerabieMessageStatus.pending);
      expect(realtime.sent.single, (conversationId: 7, body: 'Where is my order?'));

      realtime.emit('message', serverMessage(3, 'Where is my order?', role: 'customer'));

      final mine = c.messages.where((m) => m.body == 'Where is my order?');
      expect(mine, hasLength(1));
      expect(mine.single.id, '3');
      expect(mine.single.status, KerabieMessageStatus.sent);
      c.dispose();
    });

    test('ignores blank messages', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      await c.sendMessage('   ');

      expect(realtime.sent, isEmpty);
      c.dispose();
    });

    test('marks a message failed when the server never confirms, and retry sends it again', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      await c.sendMessage('Hello?');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final failed = c.messages.last;
      expect(failed.status, KerabieMessageStatus.failed);

      await c.retry(failed);
      expect(realtime.sent, hasLength(2));
      expect(c.messages.where((m) => m.body == 'Hello?'), hasLength(1));
      expect(c.messages.last.status, KerabieMessageStatus.pending);
      c.dispose();
    });

    test('the first message of a visitor with no conversation starts one', () async {
      final empty = FakeServer({
        'GET /public/widget/init': {'orgId': 42, 'settings': {}},
        'GET /public/widget/messages': {'conversationId': null, 'messages': []},
      });
      final c = makeController(realtime: realtime, server: empty);
      await c.start();
      await c.sendMessage('Hi');

      expect(realtime.sent.single.conversationId, isNull);
      realtime.emit('message', serverMessage(9, 'Hi', role: 'customer', conversationId: 55));
      expect(c.conversationId, 55);
      c.dispose();
    });
  });

  group('incoming', () {
    test('counts unread replies while the chat is closed and clears them on open', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('message', serverMessage(10, 'One'));
      realtime.emit('message', serverMessage(11, 'Two'));
      expect(c.unreadCount, 2);

      c.open();
      expect(c.unreadCount, 0);
      realtime.emit('message', serverMessage(12, 'Three'));
      expect(c.unreadCount, 0);
      c.dispose();
    });

    test('does not add the same message twice', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('message', serverMessage(10, 'One'));
      realtime.emit('message', serverMessage(10, 'One'));
      expect(c.messages.where((m) => m.id == '10'), hasLength(1));
      expect(c.unreadCount, 1);
      c.dispose();
    });

    test('treats an agent message with metadata source ai as the bot', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('message', serverMessage(10, 'I can help', metadata: {'source': 'ai'}));
      expect(c.messages.last.sender, KerabieSender.bot);
      c.dispose();
    });

    test('streams an AI reply in, then swaps it for the saved message without counting it twice', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('start', {'streamId': 's1', 'conversationId': 7});
      expect(c.messages.last.streaming, isTrue);
      realtime.emit('chunk', {'streamId': 's1', 'delta': 'Your order '});
      realtime.emit('chunk', {'streamId': 's1', 'delta': 'ships today.'});
      expect(c.messages.last.body, 'Your order ships today.');

      realtime.emit('message', serverMessage(20, 'Your order ships today.', metadata: {'source': 'ai'}, streamId: 's1'));
      expect(c.messages.last.id, '20');
      expect(c.messages.last.streaming, isFalse);
      expect(c.messages.where((m) => m.body == 'Your order ships today.'), hasLength(1));
      expect(c.unreadCount, 1);
      c.dispose();
    });

    test('shows typing, tells the AI from an agent, and clears it when the reply arrives', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('typing', {'typing': true, 'userId': 0});
      expect(c.isTyping, isTrue);
      expect(c.isAiTyping, isTrue);

      realtime.emit('typing', {'typing': true, 'userId': 5});
      expect(c.isAiTyping, isFalse);

      realtime.emit('message', serverMessage(30, 'Here'));
      expect(c.isTyping, isFalse);
      c.dispose();
    });

    test('tracks whether agents are online', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('ready', {'conversationId': 7, 'agentsOnline': true});
      expect(c.agentsOnline, 1);
      realtime.emit('agents', {'count': 3});
      expect(c.agentsOnline, 3);
      realtime.emit('ready', {'conversationId': 7, 'agentsOnline': false});
      expect(c.agentsOnline, 0);
      c.dispose();
    });

    test('after a reconnect, picks up replies that arrived while offline', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      realtime.emit('connect');
      expect(c.messages, hasLength(2));

      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [
          serverMessage(1, 'Hello', role: 'customer'),
          serverMessage(2, 'Hi, how can we help?'),
          serverMessage(3, 'Sorry for the wait'),
        ],
      };
      realtime.emit('disconnect');
      realtime.emit('connect');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.messages.map((m) => m.body), contains('Sorry for the wait'));
      expect(c.messages, hasLength(3));
      c.dispose();
    });
  });

  group('typing events', () {
    test('sends typing for the current conversation', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      c.sendTyping(true);

      expect(realtime.typing.single, (conversationId: 7, typing: true));
      c.dispose();
    });
  });

  group('push notifications', () {
    test('registers the token with the provider name the API expects', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      final ok = await c.registerPushToken('fcm-token-123', provider: KerabiePushProvider.fcm);
      expect(ok, isTrue);
      final request = server.last('POST', '/public/widget/push-token')!;
      expect(request.body, contains('"token":"fcm-token-123"'));
      expect(request.body, contains('"provider":"fcm"'));
      c.dispose();
    });

    test('reports failure when the server refuses', () async {
      final c = makeController(realtime: realtime, server: FakeServer({'GET /public/widget/init': {'orgId': 1}}));
      await c.start();

      expect(await c.registerPushToken('t', provider: KerabiePushProvider.expo), isFalse);
      c.dispose();
    });

    test('a tapped notification with a conversation id opens the chat', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = () => shown++;

      expect(c.handleNotificationData({'conversationId': '7', 'orgId': '42'}), isTrue);
      expect(c.handleNotificationData({'conversationId': 7}), isTrue);
      expect(shown, 2);
      c.dispose();
    });

    test('a notification that is not about a conversation is left alone', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = () => shown++;

      expect(c.handleNotificationData({'type': 'promo'}), isFalse);
      expect(shown, 0);
      c.dispose();
    });
  });

  group('deep links', () {
    test('opens the chat for a conversation link with any scheme by default', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = () => shown++;

      expect(c.handleDeepLink(Uri.parse('myapp://conversation/123')), isTrue);
      expect(c.handleDeepLink(Uri.parse('other://conversation/9')), isTrue);
      expect(shown, 2);
      c.dispose();
    });

    test('only accepts your own scheme when one is set', () async {
      final c = makeController(
        realtime: realtime,
        server: server,
        config: const KerabieConfig(widgetKey: 'wk', appName: 'A', appVersion: '1', deepLinkScheme: 'myapp'),
      );
      await c.start();

      expect(c.handleDeepLink(Uri.parse('myapp://conversation/123')), isTrue);
      expect(c.handleDeepLink(Uri.parse('other://conversation/123')), isFalse);
      c.dispose();
    });

    test('ignores other links and malformed ids', () {
      expect(KerabieDeepLink.conversationId(Uri.parse('myapp://settings')), isNull);
      expect(KerabieDeepLink.conversationId(Uri.parse('myapp://conversation/abc')), isNull);
      expect(KerabieDeepLink.conversationId(Uri.parse('myapp://conversation')), isNull);
    });

    test('builds a link that parses back', () {
      final uri = KerabieDeepLink.conversationUri(123, 'myapp');
      expect(uri.toString(), 'myapp://conversation/123');
      expect(KerabieDeepLink.conversationId(uri, scheme: 'myapp'), 123);
    });

    test('reads conversation ids from numbers and strings in notification data', () {
      expect(KerabieDeepLink.conversationIdFromNotification({'conversationId': 5}), 5);
      expect(KerabieDeepLink.conversationIdFromNotification({'conversationId': '5'}), 5);
      expect(KerabieDeepLink.conversationIdFromNotification({'conversationId': 'x'}), isNull);
      expect(KerabieDeepLink.conversationIdFromNotification({}), isNull);
    });
  });

  group('open and close', () {
    test('without a presenter, showChat only changes state', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      c.showChat();
      expect(c.isOpen, isTrue);
      c.close();
      expect(c.isOpen, isFalse);
      c.dispose();
    });
  });

  test('notifies listeners when the conversation changes', () async {
    final c = makeController(realtime: realtime, server: server);
    await c.start();
    var calls = 0;
    c.addListener(() => calls++);
    realtime.emit('message', serverMessage(40, 'Hey'));
    expect(calls, greaterThan(0));

    c.dispose();
  });
}
