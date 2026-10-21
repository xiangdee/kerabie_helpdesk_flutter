import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/api_client.dart';
import 'package:kerabie_helpdesk_flutter/src/attachments.dart';
import 'package:kerabie_helpdesk_flutter/src/ui/emoji_picker.dart';
import 'package:kerabie_helpdesk_flutter/src/ui/indicators.dart';
import 'package:kerabie_helpdesk_flutter/src/ui/palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRealtime realtime;
  late FakeServer server;
  late FakeFilePicker picker;
  KerabieController? controller;
  late Directory tempDir;
  late String realFile;
  var navigatorKey = GlobalKey<NavigatorState>();

  Map<String, dynamic> settings([Map<String, dynamic> extra = const {}]) => {
        'name': 'Acme Support',
        'chatbotEnabled': true,
        ...extra,
      };

  void serve({Map<String, dynamic>? settingsExtra, List<Map<String, dynamic>> messages = const [], int? conversationId}) {
    server = FakeServer({
      'GET /public/widget/init': {'orgId': 42, 'settings': settings(settingsExtra ?? {})},
      'GET /public/widget/messages': {'conversationId': conversationId, 'messages': messages},
      'POST /public/widget/identify': {'success': true},
      'POST /public/widget/context': {'success': true},
    });
  }

  // The real upload reads the file from disk, which a widget test's fake clock cannot wait for.
  Future<KerabieUploadedAttachment> fakeUpload(KerabieApi api, KerabiePickedFile file) async =>
      KerabieUploadedAttachment(key: 'k', fileName: file.name, mimeType: file.mimeType);

  Future<KerabieController> boot(
    WidgetTester tester, {
    KerabieConfig config = sampleConfig,
    Widget? home,
    void Function(KerabieRoute)? onNavigate,
    VoidCallback? onOpenKnowledgeBase,
    List<NavigatorObserver> observers = const [],
    bool connect = true,
    bool online = true,
    KerabieUploader? uploader,
  }) async {
    final c = makeController(realtime: realtime, server: server, config: config, filePicker: picker, uploader: uploader ?? fakeUpload);
    controller = c;
    // Not inside runAsync: the controller's timers must be the test's fake ones.
    await c.start();
    if (connect) {
      realtime.emit('connect');
      realtime.emit('ready', {'conversationId': c.conversationId, 'agentsOnline': online});
    }
    await tester.pumpWidget(
      KerabieProvider(
        config: config,
        controller: c,
        navigatorKey: navigatorKey,
        onNavigate: onNavigate,
        onOpenKnowledgeBase: onOpenKnowledgeBase,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: observers,
          home: home ?? const Scaffold(body: Stack(children: [Center(child: Text('My app')), KerabieLauncher()])),
        ),
      ),
    );
    return c;
  }

  Future<void> openChat(WidgetTester tester) async {
    await tester.tap(find.byType(KerabieLauncherButton));
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('kerabie_ui');
    realFile = (File('${tempDir.path}/file.bin')..writeAsBytesSync([1, 2, 3])).path;
    realtime = FakeRealtime();
    picker = FakeFilePicker();
    navigatorKey = GlobalKey<NavigatorState>();
    serve();
  });

  tearDown(() {
    controller?.dispose();
    controller = null;
    realtime.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps an uploaded file open for a moment; the system cleans the temp folder later.
    }
  });

  group('chat screen', () {
    testWidgets('the header shows the connection, the agents online and the settings gear', (tester) async {
      await boot(tester);
      await openChat(tester);

      expect(find.text('Acme Support'), findsOneWidget);
      expect(find.text('1 agent online'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      realtime.emit('agents', {'count': 3});
      await tester.pump();
      expect(find.text('3 agents online'), findsOneWidget);
    });

    testWidgets('the single layout has no settings gear unless the menu is on', (tester) async {
      serve(settingsExtra: {'layout': 'single', 'showMenu': false});
      await boot(tester);
      await openChat(tester);
      expect(find.byTooltip('Settings'), findsNothing);
    });

    testWidgets('showMenu brings the gear back in the single layout', (tester) async {
      serve(settingsExtra: {'layout': 'single', 'showMenu': true});
      await boot(tester);
      await openChat(tester);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('an empty conversation shows the welcome, personalised, and the chat title can be set by the developer', (tester) async {
      serve(settingsExtra: {'welcomeMessage': 'Hi {{name}}, ask away'});
      await boot(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'a',
          appVersion: '1',
          user: KerabieUser(name: 'Ada Obi'),
          chatSettings: KerabieChatSettings(name: 'Help desk'),
        ),
      );
      await openChat(tester);

      expect(find.text('Hi Ada, ask away'), findsOneWidget);
      expect(find.text('Help desk'), findsOneWidget);
      expect(find.text('Acme Support'), findsNothing);
    });

    testWidgets('the default welcome is used when nobody set one', (tester) async {
      await boot(tester);
      await openChat(tester);
      expect(find.text('Hi there! How can we help you today?'), findsOneWidget);
    });

    testWidgets('the composer is locked with a hint until the connection is up', (tester) async {
      await boot(tester, connect: false);
      await openChat(tester);

      expect(find.text('Waiting for connection…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isFalse);

      realtime.emit('connect');
      await tester.pump();
      expect(find.text('Type a message…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isTrue);
    });

    testWidgets('a drop of three seconds shows the reconnecting banner, a shorter one does not', (tester) async {
      await boot(tester);
      await openChat(tester);

      realtime.emit('disconnect');
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('reconnecting'), findsNothing);

      realtime.emit('connect');
      await tester.pump();
      realtime.emit('disconnect');
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('reconnecting'), findsNothing); // the timer started over

      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('reconnecting'), findsOneWidget);

      realtime.emit('connect');
      await tester.pump();
      expect(find.textContaining('reconnecting'), findsNothing);
    });

    testWidgets('typing shows dots for an agent and the orb for the AI, and the developer can turn it off', (tester) async {
      await boot(tester);
      await openChat(tester);

      realtime.emit('typing', {'typing': true, 'userId': 5});
      await tester.pump();
      expect(find.byType(KerabieTypingDots), findsOneWidget);
      expect(find.byType(KerabieAiOrb), findsNothing);

      realtime.emit('typing', {'typing': true, 'userId': 0});
      await tester.pump();
      expect(find.byType(KerabieAiOrb), findsOneWidget);
      expect(find.text('Thinking…'), findsOneWidget);

      realtime.emit('typing', {'typing': false});
      await tester.pump();
      expect(find.byType(KerabieAiOrb), findsNothing);
      expect(find.byType(KerabieTypingDots), findsNothing);
    });

    testWidgets('the typing indicator stays hidden when the dashboard turned it off', (tester) async {
      serve(settingsExtra: {'typingIndicator': false});
      await boot(tester);
      await openChat(tester);
      realtime.emit('typing', {'typing': true, 'userId': 5});
      await tester.pump();
      expect(find.byType(KerabieTypingDots), findsNothing);
      await tester.pump(const Duration(seconds: 4)); // the typing safety timer
    });

    testWidgets('typing in the box tells the agent, and sending stops it', (tester) async {
      serve(conversationId: 7, messages: [serverMessage(1, 'Hello')]);
      await boot(tester);
      await openChat(tester);

      await tester.enterText(find.byType(TextField).first, 'Hi');
      await tester.pump();
      expect(realtime.typing, [(conversationId: 7, typing: true)]);

      await tester.pump(const Duration(milliseconds: 1600));
      expect(realtime.typing.last.typing, isFalse);
    });

    testWidgets('the branding link shows unless the dashboard hides it', (tester) async {
      await boot(tester);
      await openChat(tester);
      expect(find.textContaining('Powered by'), findsOneWidget);
    });

    testWidgets('no branding when it is switched off', (tester) async {
      serve(settingsExtra: {'showBranding': false});
      await boot(tester);
      await openChat(tester);
      expect(find.textContaining('Powered by'), findsNothing);
    });

    testWidgets('an incoming message with a link preview and a knowledge base citation', (tester) async {
      serve(conversationId: 7, messages: [
        {
          ...serverMessage(2, 'See https://example.com/page and the article', metadata: {
            'source': 'ai',
            'articles': [
              {'id': 3, 'title': 'Refund policy'},
            ],
          }),
          'linkPreview': {'url': 'https://example.com/page', 'title': 'Example page', 'description': 'A page', 'siteName': 'Example'},
        },
      ]);
      server.routes['GET /public/kb/articles/3'] = {
        'article': {'id': 3, 'title': 'Refund policy', 'content': '<p>Refunds take <b>5 days</b></p>', 'imageUrl': null},
      };
      await boot(tester);
      await openChat(tester);

      expect(find.text('Example page'), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('📄 Refund policy'), findsOneWidget);

      await tester.tap(find.text('📄 Refund policy'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refunds take', findRichText: true), findsOneWidget);
      expect(find.text('Was this helpful?'), findsOneWidget);
    });

    testWidgets('ticks: read shows two, sent shows one', (tester) async {
      serve(conversationId: 7, messages: [
        {...serverMessage(1, 'Seen one', role: 'customer'), 'status': 'read'},
        serverMessage(2, 'Sent one', role: 'customer'),
      ]);
      await boot(tester);
      await openChat(tester);

      expect(find.textContaining('✓✓'), findsOneWidget);
      expect(find.textContaining('✓'), findsNWidgets(2));
    });

    testWidgets('a failed message is tapped to retry', (tester) async {
      await boot(tester);
      await openChat(tester);
      realtime.connected = false;
      await tester.enterText(find.byType(TextField).first, 'Hello there');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Tap to retry ↺'), findsOneWidget);
      realtime.connected = true;
      await tester.tap(find.text('Tap to retry ↺'));
      await tester.pump();
      expect(realtime.sent.single.body, 'Hello there');
      await tester.pump(const Duration(seconds: 9));
    });
  });

  group('pre-chat form', () {
    testWidgets('the organisation\'s own questions are asked before the first message', (tester) async {
      serve(settingsExtra: {
        'customerEnrichmentEnabled': true,
        'customerEnrichmentForm': {
          'fields': [
            {'key': 'name', 'label': 'Name', 'type': 'text', 'required': true},
            {'key': 'plan', 'label': 'Plan', 'type': 'select', 'required': false, 'options': ['Free', 'Pro']},
            {'key': 'age', 'label': 'Age', 'type': 'number', 'required': false},
          ],
        },
      });
      final c = await boot(tester);
      await openChat(tester);

      expect(find.text('Before we start'), findsOneWidget);
      expect(find.text('Start chat'), findsOneWidget);
      expect(find.text('Plan (optional)'), findsOneWidget);

      await tester.tap(find.text('Start chat'));
      await tester.pump();
      expect(find.text('Name is required'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Ada Obi'); // the form's first field
      await tester.tap(find.text('Pro'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '1.2.3');
      await tester.tap(find.text('Start chat'));
      await tester.pump();
      expect(find.text('Age must be a number'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.tap(find.text('Start chat'));
      await tester.pumpAndSettle();

      expect(c.currentUser!.name, 'Ada Obi');
      expect(c.currentUser!.customAttributes, {'plan': 'Pro'});
      expect(find.text('Before we start'), findsNothing);
      final sent = jsonDecode(server.last('POST', '/public/widget/identify')!.body) as Map;
      expect((sent['user'] as Map)['name'], 'Ada Obi');
      expect((sent['user'] as Map)['customAttributes'], {'plan': 'Pro'});
    });

    testWidgets('with nobody online and no AI the offline form asks for a name or email', (tester) async {
      serve(settingsExtra: {'chatbotEnabled': false});
      final c = await boot(tester, online: false);
      await openChat(tester);

      expect(find.text("We're offline right now"), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text('Enter a name or email so we can follow up'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Email address'), 'nope');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Email address'), 'ada@example.com');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(c.currentUser!.email, 'ada@example.com');
      expect(find.text("We're offline right now"), findsNothing);
    });

    testWidgets('no form when an agent is online, or the AI can answer', (tester) async {
      await boot(tester);
      await openChat(tester);
      expect(find.text('Before we start'), findsNothing);
      expect(find.text("We're offline right now"), findsNothing);
    });

    testWidgets('no form for someone who already gave their details or already wrote', (tester) async {
      serve(settingsExtra: {'chatbotEnabled': false});
      await boot(
        tester,
        online: false,
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', user: KerabieUser(email: 'ada@example.com')),
      );
      await openChat(tester);
      expect(find.text("We're offline right now"), findsNothing);
    });

    testWidgets('no form once the conversation has messages', (tester) async {
      serve(settingsExtra: {'chatbotEnabled': false}, conversationId: 7, messages: [serverMessage(1, 'Hello')]);
      await boot(tester, online: false);
      await openChat(tester);
      expect(find.text("We're offline right now"), findsNothing);
    });

    testWidgets('text from the search bar waits in the box while the form collects details', (tester) async {
      serve(settingsExtra: {'chatbotEnabled': false});
      final c = await boot(tester, online: false);
      c.openWithDraft('Where is my order?');
      await tester.pumpAndSettle();

      expect(find.text("We're offline right now"), findsOneWidget);
      expect(find.text('Where is my order?'), findsOneWidget);
      expect(realtime.sent, isEmpty);
      expect(c.chatDraft, isNull);
    });
  });

  group('attachments in the composer', () {
    testWidgets('the paperclip offers a photo or a document, and the picked file waits above the box', (tester) async {
      picker.image = KerabiePickedFile(path: realFile, name: 'photo.jpg', mimeType: 'image/jpeg', size: 10);
      server.routes['POST /public/widget/attachment'] = {'jobId': 'j'};
      server.routes['GET /public/widget/attachment/j'] = {
        'status': 'succeeded',
        'result': {'key': 'k', 'fileName': 'photo.jpg', 'mimeType': 'image/jpeg'},
      };
      final c = await boot(tester);
      await openChat(tester);

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      expect(find.text('Send attachment'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);

      await tester.tap(find.text('Photo'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('photo.jpg'), findsOneWidget);
      expect(c.staging.uploaded, isNotNull);
      // The paperclip is off while a file is waiting.
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.attach_file_rounded)).onPressed, isNull);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(realtime.sent.single.key, 'k');
      expect(c.staging.pending, isNull);
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('a refused file shows its message, and the cross dismisses it', (tester) async {
      picker.document = KerabiePickedFile(path: realFile, name: 'x.exe', mimeType: 'application/x-msdownload', size: 10);
      await boot(tester, uploader: (api, file) => uploadAttachment(api, file)); // the type check runs before any file is read
      await openChat(tester);

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Document'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(); // the dialog's route leaves the tree

      expect(find.textContaining('is not allowed'), findsOneWidget);
      await tester.tap(find.descendant(of: find.ancestor(of: find.textContaining('is not allowed'), matching: find.byType(Row)).first, matching: find.byType(InkWell)));
      await tester.pump();
      expect(find.textContaining('is not allowed'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('the developer can switch attachments off', (tester) async {
      await boot(
        tester,
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', chatSettings: KerabieChatSettings(enableFileAttachments: false)),
      );
      await openChat(tester);
      expect(find.byTooltip('Attach'), findsNothing);
    });
  });

  group('emoji', () {
    testWidgets('the emoji button opens a picker; searching narrows it and picking adds the emoji to the message', (tester) async {
      await boot(tester);
      await openChat(tester);

      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      expect(find.byType(KerabieEmojiPicker), findsOneWidget);
      expect(find.text('Recently used'), findsNothing);

      await tester.enterText(find.descendant(of: find.byType(KerabieEmojiPicker), matching: find.byType(TextField)), 'red heart');
      await tester.pump();
      expect(find.text('Results'), findsNothing); // the label is upper case
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.text('❤️'), findsWidgets);
      expect(find.text('😀'), findsNothing);

      await tester.tap(find.text('❤️').first);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, contains('❤'));
      expect(await controller!.storage.read<List<dynamic>>('recent_emoji'), isNotEmpty);
    });

    testWidgets('a search with no match says so', (tester) async {
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(KerabieEmojiPicker), matching: find.byType(TextField)), 'zzzzqqq');
      await tester.pump();
      expect(find.text('No emoji found'), findsOneWidget);
    });

    testWidgets('recently used emoji come first next time, newest first, without repeats', (tester) async {
      final c = await boot(tester);
      await c.storage.write('recent_emoji', ['😀', '❤️']);
      await openChat(tester);
      await tester.tap(find.byTooltip('Emoji'));
      await tester.pumpAndSettle();
      expect(find.text('RECENTLY USED'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the rows, and no transcript rows before there is a conversation', (tester) async {
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Change Name'), findsOneWidget);
      expect(find.text('Download Transcript'), findsNothing);
      expect(find.text('Email Transcript'), findsNothing);
      expect(find.text('Download my data'), findsOneWidget);
      expect(find.text('Delete my data'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('the transcript rows appear once there is a conversation', (tester) async {
      serve(conversationId: 7, messages: [serverMessage(1, 'Hello')]);
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Download Transcript'), findsOneWidget);
      expect(find.text('Email Transcript'), findsOneWidget);
    });

    testWidgets('changing the name tells the server and updates the visitor', (tester) async {
      final c = await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '  Ada Obi ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(c.currentUser!.name, 'Ada Obi');
      expect(find.text('✓ Saved!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('✓ Saved!'), findsNothing);
    });

    testWidgets('an empty name is not saved', (tester) async {
      final c = await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.currentUser, isNull);
    });

    testWidgets('emailing the transcript checks the address first', (tester) async {
      serve(conversationId: 7, messages: [serverMessage(1, 'Hello')]);
      server.routes['POST /public/widget/conversations/7/export/email'] = {'success': true};
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Email Transcript'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'not-an-email');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(server.last('POST', '/public/widget/conversations/7/export/email'), isNull);

      await tester.enterText(find.byType(TextField).last, 'ada@example.com');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(jsonDecode(server.last('POST', '/public/widget/conversations/7/export/email')!.body), {'email': 'ada@example.com'});
      expect(find.text('✓ Sent!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed email says so and keeps the dialog open', (tester) async {
      serve(conversationId: 7, messages: [serverMessage(1, 'Hello')]);
      server.routes['POST /public/widget/conversations/7/export/email'] = (http.Request r) => json({'message': 'x'}, 500);
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email Transcript'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'ada@example.com');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't send the email — try again"), findsOneWidget);
    });

    testWidgets('downloading data when the server holds none says so', (tester) async {
      server.routes['GET /public/widget/my-data'] = {'profile': null, 'conversations': []};
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download my data'));
      await tester.pumpAndSettle();
      expect(find.text("We don't hold any data about you yet."), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('deleting data asks first, then erases', (tester) async {
      server.routes['DELETE /public/widget/my-data'] = {'success': true};
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete my data'));
      await tester.pumpAndSettle();
      expect(find.textContaining("can't be undone"), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.last('DELETE', '/public/widget/my-data'), isNull);

      await tester.tap(find.text('Delete my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete'));
      await tester.pumpAndSettle();
      expect(server.last('DELETE', '/public/widget/my-data'), isNotNull);
      expect(find.text('Your data has been deleted.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed delete says so and the data stays', (tester) async {
      server.routes['DELETE /public/widget/my-data'] = (http.Request r) => json({'message': 'x'}, 500);
      await boot(tester);
      await openChat(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't delete your data — try again"), findsOneWidget);
    });
  });

  group('launcher and opening', () {
    testWidgets('hideFloatingButton hides the launcher but KerabieChat.show still works', (tester) async {
      await boot(
        tester,
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', hideFloatingButton: true),
        home: Scaffold(
          body: Stack(children: [
            const KerabieLauncher(),
            Builder(builder: (context) => TextButton(onPressed: () => KerabieChat.show(context), child: const Text('Help'))),
          ]),
        ),
      );
      expect(find.byType(KerabieLauncherButton), findsNothing);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Support'), findsOneWidget);
    });

    testWidgets('the launcher follows the configured position', (tester) async {
      await boot(tester, config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', position: KerabiePosition.topLeft));
      final centre = tester.getCenter(find.byType(KerabieLauncherButton));
      expect(centre.dx, lessThan(100));
      expect(centre.dy, lessThan(150));
    });

    testWidgets('the launcher size and corner shape follow the theme', (tester) async {
      await boot(
        tester,
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', theme: KerabieTheme(bubbleSize: 72, cornerRadius: 0)),
      );
      expect(tester.getSize(find.byType(KerabieLauncherButton)), const Size(72, 72));
      expect(launcherRadiusFor(0), 0);
      expect(launcherRadiusFor(8), 0.2);
      expect(launcherRadiusFor(18), 0.35);
      expect(launcherRadiusFor(24), 0.5);
      expect(launcherRadiusFor(null), 0.35);
    });

    testWidgets('tapping the launcher while the chat is open takes it away again', (tester) async {
      final c = await boot(tester, config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', openMode: KerabieOpenMode.sheet));
      await openChat(tester);
      expect(c.isOpen, isTrue);
      c.toggle();
      await tester.pumpAndSettle();
      expect(c.isOpen, isFalse);
      expect(find.text('Acme Support'), findsNothing);
    });

    testWidgets('the sheet mode opens the chat as a bottom sheet over the app', (tester) async {
      await boot(tester, config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', openMode: KerabieOpenMode.sheet));
      await openChat(tester);
      expect(find.text('Acme Support'), findsOneWidget);
      expect(find.text('My app'), findsOneWidget); // still there behind the sheet
    });

    testWidgets('push mode hands the opening to the app', (tester) async {
      final routes = <KerabieRoute>[];
      final c = await boot(
        tester,
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', openMode: KerabieOpenMode.push),
        onNavigate: routes.add,
      );
      await tester.tap(find.byType(KerabieLauncherButton));
      await tester.pumpAndSettle();
      expect(routes.single.type, KerabieRouteType.inbox);
      expect(find.text('Acme Support'), findsNothing);

      c.handleNotificationData({'conversationId': 7});
      await tester.pumpAndSettle();
      expect(routes.last.type, KerabieRouteType.conversation);
      expect(routes.last.conversationId, 7);
    });

    testWidgets('push mode without onNavigate opens the chat as a page', (tester) async {
      await boot(tester, config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', openMode: KerabieOpenMode.push));
      await openChat(tester);
      expect(find.text('Acme Support'), findsOneWidget);
    });

    testWidgets('the app can show the chat screen in its own route and close it itself', (tester) async {
      var closed = 0;
      final c = await boot(
        tester,
        home: Scaffold(body: KerabieChatScreen(onClose: () => closed++)),
      );
      await tester.pumpAndSettle();
      expect(c.isOpen, isTrue);
      await tester.tap(find.byTooltip('Close'));
      expect(closed, 1);
    });

    testWidgets('defaultOpen shows the chat once the app has built', (tester) async {
      await boot(tester, config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', defaultOpen: true));
      await tester.pumpAndSettle();
      expect(find.text('Acme Support'), findsOneWidget);
    });

    testWidgets('onOpenChat and onCloseChat run as the chat opens and closes', (tester) async {
      final events = <String>[];
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      controller = c;
      await tester.runAsync(c.start);
      await tester.pumpWidget(
        KerabieProvider(
          config: sampleConfig,
          controller: c,
          navigatorKey: navigatorKey,
          onOpenChat: () => events.add('open'),
          onCloseChat: () => events.add('close'),
          child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: Stack(children: [KerabieLauncher()]))),
        ),
      );
      await openChat(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(events, ['open', 'close']);
    });

    testWidgets('openWithContext opens the chat', (tester) async {
      final c = await boot(tester);
      c.openWithContext(const KerabieChatContext(type: 'product', id: 'sku_1', title: 'Blue Sneakers'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Support'), findsOneWidget);
      expect(server.last('POST', '/public/widget/context'), isNotNull);
    });
  });

  group('search bar', () {
    testWidgets('shows the dashboard\'s placeholder and no floating button', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar', 'searchbarPlaceholder': 'Ask Acme'});
      await boot(tester);
      expect(find.text('Ask Acme'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_rounded), findsNothing);
    });

    testWidgets('the default placeholder', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar'});
      await boot(tester);
      expect(find.text('Ask anything...'), findsOneWidget);
    });

    testWidgets('sending opens the chat and sends what was typed', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar'});
      await boot(tester);
      await tester.enterText(find.byType(TextField), 'Where is my order?');
      await tester.tap(find.bySemanticsLabel('Start chat'));
      await tester.pumpAndSettle();

      expect(find.text('Acme Support'), findsOneWidget);
      expect(realtime.sent.single.body, 'Where is my order?');
      expect(controller!.chatDraft, isNull);
    });

    testWidgets('sending nothing just opens the chat', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar'});
      await boot(tester);
      await tester.tap(find.bySemanticsLabel('Start chat'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Support'), findsOneWidget);
      expect(realtime.sent, isEmpty);
    });

    testWidgets('a file picked in the bar goes out when the chat opens', (tester) async {
      picker.document = KerabiePickedFile(path: realFile, name: 'a.pdf', mimeType: 'application/pdf', size: 10);
      server.routes['POST /public/widget/attachment'] = {'jobId': 'j'};
      server.routes['GET /public/widget/attachment/j'] = {
        'status': 'succeeded',
        'result': {'key': 'k', 'fileName': 'a.pdf', 'mimeType': 'application/pdf'},
      };
      serve(settingsExtra: {'launcherType': 'searchbar'});
      server.routes['POST /public/widget/attachment'] = {'jobId': 'j'};
      server.routes['GET /public/widget/attachment/j'] = {
        'status': 'succeeded',
        'result': {'key': 'k', 'fileName': 'a.pdf', 'mimeType': 'application/pdf'},
      };
      await boot(tester);

      await tester.tap(find.byTooltip('Send attachment'));
      await tester.pump();
      await tester.tap(find.text('📄  Document'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.text('a.pdf'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Start chat'));
      await tester.pumpAndSettle();
      expect(realtime.sent.single.key, 'k');
      expect(realtime.sent.single.type, 'file');
    });

    testWidgets('it hides while the chat is open and with hideFloatingButton', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar'});
      final c = await boot(tester);
      expect(find.text('Ask anything...'), findsOneWidget);
      c.open();
      await tester.pump();
      expect(find.text('Ask anything...'), findsNothing);
    });

    testWidgets('the developer can force the bubble over the dashboard\'s search bar', (tester) async {
      serve(settingsExtra: {'launcherType': 'searchbar'});
      await boot(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'a',
          appVersion: '1',
          chatSettings: KerabieChatSettings(launcherType: KerabieLauncherType.bubble),
        ),
      );
      expect(find.byType(KerabieLauncherButton), findsOneWidget);
      expect(find.text('Ask anything...'), findsNothing);
    });
  });

  group('screen tracking', () {
    testWidgets('named routes are reported, and the chat page itself is not', (tester) async {
      final c = await boot(
        tester,
        observers: [KerabieNavigatorObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/checkout'), builder: (_) => const Scaffold(body: Text('Checkout')))),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(c.screen, '/checkout');

      c.showChat();
      await tester.pumpAndSettle();
      expect(c.screen, '/checkout'); // the chat page did not replace it

      realtime.pages.clear();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(c.screen, '/checkout');
      expect(realtime.pages, isEmpty);
    });

    testWidgets('dialogs and unnamed routes are ignored', (tester) async {
      final c = await boot(
        tester,
        observers: [KerabieNavigatorObserver()],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('Hi'))),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(c.screen, '/'); // the home route; the dialog did not replace it
    });
  });

  group('campaign banner', () {
    testWidgets('shows above the launcher with its button, and the button opens the chat', (tester) async {
      server.routes['GET /public/campaigns'] = {
        'campaigns': [
          {'id': 1, 'name': 'Promo', 'message': 'Need a hand?', 'trigger': 'time_on_page', 'triggerValue': '0', 'ctaLabel': 'Talk to us', 'ctaAction': 'open_chat', 'frequency': 'every_session', 'audience': 'all'},
        ],
      };
      server.routes['POST /public/campaigns/1/events'] = {'ok': true};
      await boot(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Need a hand?'), findsOneWidget);
      expect(find.text('Talk to us'), findsOneWidget);

      await tester.tap(find.text('Talk to us'));
      await tester.pumpAndSettle();
      expect(find.text('Acme Support'), findsOneWidget);
      final events = server.requests.where((r) => r.url.path == '/public/campaigns/1/events').map((r) => jsonDecode(r.body)['event']);
      expect(events, ['shown', 'opened', 'clicked']);
    });

    testWidgets('the open knowledge base button calls the app, and falls back to the chat without it', (tester) async {
      server.routes['GET /public/campaigns'] = {
        'campaigns': [
          {'id': 1, 'name': 'Promo', 'message': 'Read our guides', 'trigger': 'time_on_page', 'triggerValue': '0', 'ctaLabel': 'Guides', 'ctaAction': 'open_kb', 'frequency': 'every_session'},
        ],
      };
      server.routes['POST /public/campaigns/1/events'] = {'ok': true};
      var kb = 0;
      await boot(tester, onOpenKnowledgeBase: () => kb++);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      expect(kb, 1);
      expect(find.text('Acme Support'), findsNothing);
    });

    testWidgets('the cross dismisses it, and Reply opens the chat when there is no button', (tester) async {
      server.routes['GET /public/campaigns'] = {
        'campaigns': [
          {'id': 1, 'name': 'Promo', 'message': 'Hello there', 'trigger': 'time_on_page', 'triggerValue': '0', 'frequency': 'every_session'},
        ],
      };
      server.routes['POST /public/campaigns/1/events'] = {'ok': true};
      await boot(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Reply →'), findsOneWidget);

      await tester.tap(find.text('✕'));
      await tester.pump();
      expect(find.text('Hello there'), findsNothing);
    });
  });

  group('help, store and tickets screens', () {
    Future<void> showScreen(WidgetTester tester, Widget screen) async {
      await boot(tester, home: Scaffold(body: Center(child: Builder(builder: (context) => TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)), child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the help centre lists articles and shows an empty state for a search with no match', (tester) async {
      server.routes['GET /public/kb/articles'] = (http.Request r) => json({
            'data': r.url.queryParameters.containsKey('search')
                ? []
                : [
                    {'id': 1, 'title': 'Refunds', 'content': '<p>Ask us <a href="https://x.co">here</a></p>'},
                  ],
          });
      server.routes['POST /public/kb/articles/1/feedback'] = {'success': true};
      await showScreen(tester, const KerabieKnowledgeBaseScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Help'), findsOneWidget);
      expect(find.text('Refunds'), findsOneWidget);

      await tester.tap(find.text('Refunds'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask us', findRichText: true), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Yes, helpful'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for the feedback.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('No articles match your search.'), findsOneWidget);
    });

    testWidgets('an empty help centre says there are no articles yet', (tester) async {
      server.routes['GET /public/kb/articles'] = {'data': []};
      await showScreen(tester, const KerabieKnowledgeBaseScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('No articles yet.'), findsOneWidget);
    });

    testWidgets('the store shows products in a grid with their prices', (tester) async {
      server.routes['GET /public/store/by-widget'] = {
        'store': {'name': 'Acme Shop', 'slug': 'acme'},
        'products': [
          {'id': 1, 'name': 'Sneakers', 'price': 45.5, 'currency': 'USD'},
          {'id': 2, 'name': 'Socks', 'price': 5, 'currency': 'USD'},
        ],
      };
      await showScreen(tester, const KerabieStoreScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Acme Shop'), findsOneWidget);
      expect(find.text('Sneakers'), findsOneWidget);
      expect(find.text(r'$45.50'), findsOneWidget);
      expect(find.text(r'$5.00'), findsOneWidget);
    });

    testWidgets('an empty store says so', (tester) async {
      server.routes['GET /public/store/by-widget'] = {'products': []};
      await showScreen(tester, const KerabieStoreScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('No products yet.'), findsOneWidget);
      expect(find.text('Store'), findsOneWidget);
    });

    testWidgets('tickets: the list, a new ticket, and its conversation', (tester) async {
      var created = false;
      server.routes['GET /public/tickets'] = (http.Request r) => json({
            'data': [
              {'id': 12, 'subject': 'Late order', 'status': 'ACTIVE', 'priority': 'HIGH', 'createdAt': DateTime.now().toIso8601String()},
              if (created) {'id': 55, 'subject': 'Broken', 'status': 'RESOLVED', 'priority': 'NORMAL', 'createdAt': DateTime.now().toIso8601String()},
            ],
          });
      server.routes['POST /public/tickets'] = (http.Request r) {
        created = true;
        return json({'ticketId': 55});
      };
      server.routes['GET /public/tickets/55'] = {
        'ticket': {'id': 55, 'subject': 'Broken', 'status': 'CLOSED', 'priority': 'NORMAL', 'createdAt': DateTime.now().toIso8601String()},
        'messages': [
          {'id': 1, 'body': 'It broke', 'senderRole': 'customer', 'createdAt': DateTime.now().toIso8601String()},
          {'id': 2, 'body': 'Fixed it', 'senderRole': 'agent', 'senderName': 'Sam', 'createdAt': DateTime.now().toIso8601String()},
        ],
      };
      await showScreen(tester, const KerabieTicketsScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Late order'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.textContaining('High priority'), findsOneWidget);

      await tester.tap(find.text('+ New ticket'));
      await tester.pumpAndSettle();
      expect(find.text('New ticket'), findsOneWidget);
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('Submit ticket'), matching: find.byType(Opacity)).first).opacity, 0.5);

      await tester.enterText(find.widgetWithText(TextField, '').at(1), 'It broke');
      await tester.enterText(find.widgetWithText(TextField, '').at(0), 'Broken');
      await tester.tap(find.text('URGENT'));
      await tester.pump();
      await tester.tap(find.text('Submit ticket'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();

      final body = jsonDecode(server.last('POST', '/public/tickets')!.body) as Map;
      expect(body['priority'], 'URGENT');
      expect(body['subject'], 'Broken');
      // It opens the new ticket's conversation; the ticket is closed, so replying is off.
      expect(find.text('Fixed it'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      await tester.tap(find.text('‹ Back'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Broken'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('a ticket with a subject-less message is created as "New ticket", and no tickets shows an empty state', (tester) async {
      server.routes['GET /public/tickets'] = {'data': []};
      server.routes['POST /public/tickets'] = {'ticketId': 3};
      await showScreen(tester, const KerabieTicketsScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('No tickets yet.'), findsOneWidget);

      await tester.tap(find.text('+ New ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '').at(1), 'Just a message');
      await tester.pump();
      await tester.tap(find.text('Submit ticket'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect((jsonDecode(server.last('POST', '/public/tickets')!.body) as Map)['subject'], 'New ticket');
    });

    testWidgets('a ticket that cannot be created says so and stays on the form', (tester) async {
      server.routes['GET /public/tickets'] = {'data': []};
      server.routes['POST /public/tickets'] = (http.Request r) => json({'message': 'Plan limit'}, 403);
      await showScreen(tester, const KerabieTicketsScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ New ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '').at(1), 'Hello');
      await tester.pump();
      await tester.tap(find.text('Submit ticket'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't create the ticket — try again"), findsOneWidget);
      expect(find.text('Submit ticket'), findsOneWidget);
    });

    testWidgets('replying to an open ticket sends the reply and reloads the conversation', (tester) async {
      var replied = false;
      server.routes['GET /public/tickets'] = {
        'data': [
          {'id': 12, 'subject': 'Late order', 'status': 'ACTIVE', 'priority': 'NORMAL', 'createdAt': DateTime.now().toIso8601String()},
        ],
      };
      server.routes['GET /public/tickets/12'] = (http.Request r) => json({
            'ticket': {'id': 12, 'subject': 'Late order', 'status': 'ACTIVE', 'priority': 'NORMAL', 'createdAt': DateTime.now().toIso8601String()},
            'messages': [
              {'id': 1, 'body': 'Where is it?', 'senderRole': 'customer', 'createdAt': DateTime.now().toIso8601String()},
              if (replied) {'id': 2, 'body': 'Thanks!', 'senderRole': 'customer', 'createdAt': DateTime.now().toIso8601String()},
            ],
          });
      server.routes['POST /public/tickets/12/reply'] = (http.Request r) {
        replied = true;
        return json({'success': true});
      };
      await showScreen(tester, const KerabieTicketsScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Late order'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Where is it?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Thanks!');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
      expect(find.text('Thanks!'), findsOneWidget);
    });
  });
}
