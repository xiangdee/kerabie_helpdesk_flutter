import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/ui/indicators.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime realtime;
  late FakeServer server;
  late KerabieController controller;
  final navigatorKey = GlobalKey<NavigatorState>();

  Widget app() => KerabieProvider(
        config: sampleConfig,
        controller: controller,
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(
            body: Stack(children: [Center(child: Text('My app')), KerabieLauncher()]),
          ),
        ),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    realtime = FakeRealtime();
    server = FakeServer({
      'GET /public/widget/init': {
        'orgId': 42,
        'settings': {'name': 'Acme Support', 'welcomeMessage': 'Hi, how can we help?'},
      },
      'GET /public/widget/messages': {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Welcome back')],
      },
      'GET /public/widget/conversations': {
        'conversations': [
          {'id': 7, 'name': 'Support Agent', 'lastMessage': 'Welcome back', 'lastMessageTime': '2026-01-01T10:00:00Z', 'unreadCount': 0},
        ],
      },
    });
    controller = makeController(realtime: realtime, server: server);
    await controller.start();
    realtime.emit('connect');
  });

  tearDown(() => controller.dispose());

  testWidgets('the launcher shows an unread badge and opens the chat', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('My app'), findsOneWidget);
    expect(find.byType(KerabieLauncherButton), findsOneWidget);

    realtime.emit('message', serverMessage(2, 'New reply'));
    realtime.emit('message', serverMessage(3, 'Another'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    // The visitor's existing conversation: Chat tab, then the row.
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Support'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(controller.isOpen, isTrue);
    expect(controller.unreadCount, 0);
  });

  testWidgets('writing a message sends it and shows it as sending', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    // Into the visitor's existing conversation (a fresh chat with nobody online asks for contact details first).
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support Agent'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Where is my order?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(realtime.sent.single.body, 'Where is my order?');
    expect(find.text('Where is my order?'), findsOneWidget);
    expect(find.byType(KerabieSendingDots), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tap to retry ↺'), findsOneWidget);
  });

  testWidgets('closing the chat marks it closed again', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    await enterChat(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    expect(find.text('Acme Support'), findsNothing);
  });

  testWidgets('a notification tap opens the chat through the navigator key', (tester) async {
    await tester.pumpWidget(app());

    expect(controller.handleNotificationData({'conversationId': '7'}), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Acme Support'), findsOneWidget);
  });

  testWidgets('a conversation with no messages yet shows the welcome message with the first name filled in', (tester) async {
    final empty = FakeServer({
      'GET /public/widget/init': {
        'orgId': 42,
        'settings': {'name': 'Acme Support', 'welcomeMessage': 'Hi {{name}}, how can we help?'},
      },
      'GET /public/widget/messages': {'conversationId': null, 'messages': []},
    });
    final fresh = makeController(
      realtime: realtime,
      server: empty,
      config: const KerabieConfig(widgetKey: 'wk_test', appName: 'Test app', appVersion: '1', user: KerabieUser(name: 'Ada Obi')),
    );
    await fresh.start();
    realtime.emit('connect');
    await tester.pumpWidget(
      KerabieProvider(
        config: sampleConfig,
        controller: fresh,
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Stack(children: [Center(child: Text('My app')), KerabieLauncher()])),
        ),
      ),
    );
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    await enterChat(tester);

    expect(find.text('Hi Ada, how can we help?'), findsOneWidget);
    fresh.dispose();
  });

  testWidgets('the guided flow opens the chat with its question and buttons, and a tap sends the choice', (tester) async {
    final guided = FakeServer({
      'GET /public/widget/init': {
        'orgId': 42,
        'settings': {
          'name': 'Acme Support',
          'welcomeMessage': 'Hello',
          'chatbotEnabled': true,
          'guidedGreeting': {
            'flowId': 'f1',
            'message': 'What would you like help with?',
            'choices': [
              {'id': 'plan', 'label': 'Help me choose a plan'},
              {'id': 'sales', 'label': 'Chat with sales'},
            ],
          },
        },
      },
      'GET /public/widget/messages': {'conversationId': null, 'messages': []},
    });
    final fresh = makeController(realtime: realtime, server: guided);
    await fresh.start();
    realtime.emit('connect');
    await tester.pumpWidget(
      KerabieProvider(
        config: sampleConfig,
        controller: fresh,
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Stack(children: [Center(child: Text('My app')), KerabieLauncher()])),
        ),
      ),
    );
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    await enterChat(tester);

    expect(find.text('What would you like help with?'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('Help me choose a plan'), findsOneWidget);
    expect(find.text('Chat with sales'), findsOneWidget);

    await tester.tap(find.text('Help me choose a plan'));
    await tester.pump();

    expect(realtime.sent.single.body, 'Help me choose a plan');
    expect(realtime.choices.single, (flowId: 'f1', choiceId: 'plan'));
    await tester.pump(const Duration(milliseconds: 100)); // the unsent message's timeout fires
    fresh.dispose();
  });

  testWidgets('buttons on the latest bot message show until the visitor answers it', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    await enterChat(tester);
    expect(find.text('Yes please'), findsNothing);

    realtime.emit('message', {
      ...serverMessage(9, 'Want a demo?'),
      'metadata': {
        'source': 'guided',
        'flowId': 'f1',
        'choices': [{'id': 'y', 'label': 'Yes please'}],
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Yes please'), findsOneWidget);

    await tester.tap(find.text('Yes please'));
    await tester.pump();
    expect(realtime.choices.single, (flowId: 'f1', choiceId: 'y'));
    await tester.pump(const Duration(milliseconds: 100)); // the unsent message's timeout fires
  });

  testWidgets('an empty chat asks again for the opening question of the screen the visitor is on', (tester) async {
    final flow = FakeServer({
      'GET /public/widget/init': {
        'orgId': 42,
        'settings': {'name': 'Acme Support', 'chatbotEnabled': true},
      },
      'GET /public/widget/messages': {'conversationId': null, 'messages': []},
      'GET /public/widget/greeting': {
        'guidedGreeting': {
          'flowId': 'f2',
          'message': 'Questions about pricing?',
          'choices': [{'id': 'p', 'label': 'See plans'}],
        },
      },
    });
    final fresh = makeController(realtime: realtime, server: flow);
    await fresh.start();
    realtime.emit('connect');
    await tester.pumpWidget(
      KerabieProvider(
        config: sampleConfig,
        controller: fresh,
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Stack(children: [Center(child: Text('My app')), KerabieLauncher()])),
        ),
      ),
    );
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
    await enterChat(tester);

    expect(find.text('Questions about pricing?'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    fresh.dispose();
  });
}
