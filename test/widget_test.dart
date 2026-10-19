import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
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
    });
    controller = makeController(realtime: realtime, server: server);
    await controller.start();
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

    expect(find.text('Acme Support'), findsOneWidget);
    expect(find.text('New reply'), findsOneWidget);
    expect(controller.isOpen, isTrue);
    expect(controller.unreadCount, 0);
  });

  testWidgets('writing a message sends it and shows it as sending', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Where is my order?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(realtime.sent.single.body, 'Where is my order?');
    expect(find.text('Where is my order?'), findsOneWidget);
    expect(find.text('Sending'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Not sent. Tap to retry'), findsOneWidget);
  });

  testWidgets('closing the chat marks it closed again', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();

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

  testWidgets('shows the welcome message from the dashboard above the history', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();

    expect(find.text('Hi, how can we help?'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
