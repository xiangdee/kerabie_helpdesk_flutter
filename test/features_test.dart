import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

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
          'welcomeMessage': 'Hi {{name}}!',
          'showBranding': true,
          'typingIndicator': true,
          'layout': 'single',
          'showMenu': false,
          'launcherType': 'searchbar',
          'searchbarPlaceholder': 'Ask Acme',
          'customerEnrichmentEnabled': true,
          'customerEnrichmentForm': {
            'fields': [
              {'key': 'name', 'label': 'Name', 'type': 'text', 'required': true},
              {'key': 'plan', 'label': 'Plan', 'type': 'select', 'required': false, 'options': ['Free', 'Pro']},
            ],
          },
          'ticketsEnabled': true,
        },
      },
      'GET /public/widget/messages': {'conversationId': null, 'messages': []},
      'POST /public/widget/identify': {'success': true},
      'POST /public/widget/context': {'success': true},
    });
  });

  tearDown(() => realtime.dispose());

  group('chat settings', () {
    test('the dashboard values are read, and what the developer sets wins', () async {
      final c = makeController(
        realtime: realtime,
        server: server,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'a',
          appVersion: '1',
          chatSettings: KerabieChatSettings(name: 'My own title', showBranding: false),
        ),
      );
      await c.start();

      expect(c.settings.chat.name, 'Acme Support');
      expect(c.chat.name, 'My own title');
      expect(c.chat.showBranding, isFalse);
      expect(c.chat.layout, KerabieLayout.single);
      expect(c.chat.showMenu, isFalse);
      expect(c.chat.launcherType, KerabieLauncherType.searchbar);
      expect(c.chat.searchbarPlaceholder, 'Ask Acme');
      expect(c.chat.customerEnrichmentEnabled, isTrue);
      expect(c.chat.customerEnrichmentForm!.map((f) => f.key), ['name', 'plan']);
      expect(c.chat.customerEnrichmentForm!.last.options, ['Free', 'Pro']);
      expect(c.settings.ticketsEnabled, isTrue);
      c.dispose();
    });

    test('{{name}} becomes the first name, or disappears with the space before it', () {
      expect(kerabiePersonalize('Hi {{name}} 👋', 'Ada Obi'), 'Hi Ada 👋');
      expect(kerabiePersonalize('Hi {{ NAME }}!', 'Ada'), 'Hi Ada!');
      expect(kerabiePersonalize('Hi {{name}} 👋', ''), 'Hi 👋');
      expect(kerabiePersonalize('Hi {{name}} 👋', null), 'Hi 👋');
      expect(kerabiePersonalize('No token', 'Ada'), 'No token');
    });
  });

  group('identity', () {
    test('setUser tells the server, and visitorName follows', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      await c.setUser(const KerabieUser(name: 'Ada Obi', email: 'ada@example.com', role: 'customer'));

      final body = jsonDecode(server.last('POST', '/public/widget/identify')!.body) as Map;
      expect(body['user'], containsPair('email', 'ada@example.com'));
      expect(body['user'], containsPair('role', 'customer'));
      expect(c.visitorName, 'Ada Obi');
      c.dispose();
    });

    test('updateAttribute keeps the other attributes and sends the whole user', () async {
      final c = makeController(
        realtime: realtime,
        server: server,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'a',
          appVersion: '1',
          user: KerabieUser(name: 'Ada', customAttributes: {'plan': 'free'}),
        ),
      );
      await c.start();
      await c.updateAttribute('cart_value', '12.50');

      expect(c.currentUser!.customAttributes, {'plan': 'free', 'cart_value': '12.50'});
      final body = jsonDecode(server.last('POST', '/public/widget/identify')!.body) as Map;
      expect((body['user'] as Map)['customAttributes'], {'plan': 'free', 'cart_value': '12.50'});
      c.dispose();
    });

    test('updateAttribute works before anyone has been identified', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      await c.updateAttribute('plan', 'pro');
      expect(c.currentUser!.customAttributes, {'plan': 'pro'});
      c.dispose();
    });

    test('clearUser empties the chat and starts a fresh anonymous session', () async {
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Hello', role: 'customer')],
      };
      var n = 0;
      final c = makeController(
        realtime: realtime,
        server: server,
        generateSession: () => 'ks_${++n}',
        config: const KerabieConfig(widgetKey: 'wk_test', appName: 'a', appVersion: '1', user: KerabieUser(name: 'Ada')),
      );
      await c.start();
      expect(c.sessionId, 'ks_1');
      expect(c.messages, hasLength(1));

      await c.clearUser();

      expect(c.currentUser, isNull);
      expect(c.messages, isEmpty);
      expect(c.conversationId, isNull);
      expect(c.sessionId, 'ks_2');
      expect(realtime.connectArgs, containsPair('sessionId', 'ks_2'));
      c.dispose();
    });

    test('setAppVersion is sent with the next connection', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      c.setAppVersion('2.0.0');
      expect(c.appVersion, '2.0.0');
      c.dispose();
    });
  });

  group('context and drafts', () {
    test('openWithContext records the context for the agent and opens the chat', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = (_) => shown++;

      c.openWithContext(const KerabieChatContext(type: 'order', id: 'ORD-1', title: 'Order #1', data: {'status': 'shipped'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final body = jsonDecode(server.last('POST', '/public/widget/context')!.body) as Map;
      expect(body, {'contextType': 'order', 'contextId': 'ORD-1', 'contextTitle': 'Order #1', 'contextData': {'status': 'shipped'}});
      expect(shown, 1);
      c.dispose();
    });

    test('openWithContext with openChat false only records it', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = (_) => shown++;

      c.openWithContext(const KerabieChatContext(type: 'custom', openChat: false));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(server.last('POST', '/public/widget/context'), isNotNull);
      expect(shown, 0);
      c.dispose();
    });

    test('a failing context request does not stop the chat from opening', () async {
      server.routes.remove('POST /public/widget/context');
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = (_) => shown++;

      c.openWithContext(const KerabieChatContext(type: 'order'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(shown, 1);
      c.dispose();
    });

    test('openWithDraft keeps the text for the chat screen and opens the chat', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      var shown = 0;
      c.presenter = (_) => shown++;

      c.openWithDraft('Where is my order?');
      expect(c.chatDraft, 'Where is my order?');
      expect(shown, 1);
      c.clearChatDraft();
      expect(c.chatDraft, isNull);
      c.dispose();
    });

    test('opening and closing tell the app', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final calls = <String>[];
      c.onOpenChat = () => calls.add('open');
      c.onCloseChat = () => calls.add('close');

      c.open();
      c.open();
      c.close();
      c.close();
      expect(calls, ['open', 'close']);
      c.dispose();
    });

    test('a notification tap for another conversation loads that conversation', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 9,
        'messages': [serverMessage(5, 'About the refund', conversationId: 9)],
      };
      KerabieRoute? route;
      c.presenter = (r) => route = r;

      expect(c.handleNotificationData({'conversationId': 9}), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(route!.type, KerabieRouteType.conversation);
      expect(route!.conversationId, 9);
      expect(server.last('GET', '/public/widget/messages')!.url.queryParameters['conversationId'], '9');
      expect(c.messages.single.body, 'About the refund');
      expect(c.conversationId, 9);
      c.dispose();
    });

    test('a notification for a conversation that is not theirs leaves the screen alone', () async {
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Mine')],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      server.routes['GET /public/widget/messages'] = {'conversationId': null, 'messages': []};
      c.presenter = (_) {};

      c.handleNotificationData({'conversationId': 99});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.messages.single.body, 'Mine');
      expect(c.conversationId, 7);
      c.dispose();
    });
  });

  group('sending', () {
    test('a message sent while the connection is down fails at once and can be retried', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      realtime.connected = false;

      await c.sendMessage('Hello?');
      expect(c.messages.single.status, KerabieMessageStatus.failed);
      expect(realtime.sent, isEmpty);

      realtime.connected = true;
      await c.retry(c.messages.single);
      expect(realtime.sent.single.body, 'Hello?');
      expect(c.messages.single.status, KerabieMessageStatus.pending);
      c.dispose();
    });

    test('a second message sent before the first is confirmed joins the same new conversation', () async {
      final c = makeController(realtime: realtime, server: server, sendTimeout: const Duration(seconds: 5));
      await c.start();

      await c.sendMessage('First');
      final second = c.sendMessage('Second');
      expect(realtime.sent, hasLength(1));
      expect(realtime.sent.single.conversationId, isNull);

      realtime.emit('message', serverMessage(1, 'First', role: 'customer', conversationId: 31));
      await second;

      expect(realtime.sent, hasLength(2));
      expect(realtime.sent.last.conversationId, 31);
      c.dispose();
    });

    test('a first message that never gets confirmed lets the next one start its own conversation', () async {
      final c = makeController(realtime: realtime, server: server, sendTimeout: const Duration(milliseconds: 30));
      await c.start();

      await c.sendMessage('First');
      final second = c.sendMessage('Second');
      await second;

      expect(c.messages.first.status, KerabieMessageStatus.failed);
      expect(realtime.sent.last.conversationId, isNull);
      c.dispose();
    });

    test('a link preview arrives for a message that is already shown', () async {
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(4, 'See https://example.com')],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      realtime.emit('linkpreview', {
        'messageId': 4,
        'linkPreview': {'url': 'https://example.com', 'title': 'Example', 'description': 'A site', 'siteName': 'Example'},
      });

      expect(c.messages.single.linkPreview!.title, 'Example');
      expect(c.messages.single.linkPreview!.url, 'https://example.com');
      c.dispose();
    });

    test('the articles an AI reply was based on are available as citations', () {
      final m = KerabieMessage.fromServer(serverMessage(1, 'Here you go', metadata: {
        'source': 'ai',
        'articles': [
          {'id': 3, 'title': 'Refunds'},
          {'id': 'bad'},
        ],
      }));
      expect(m.sender, KerabieSender.bot);
      expect(m.citations.map((c) => (c.id, c.title)), [(3, 'Refunds')]);
    });

    test('server statuses show as delivered and read', () {
      expect(KerabieMessage.fromServer({...serverMessage(1, 'a', role: 'customer'), 'status': 'read'}).status, KerabieMessageStatus.read);
      expect(KerabieMessage.fromServer({...serverMessage(1, 'a', role: 'customer'), 'status': 'delivered'}).status, KerabieMessageStatus.delivered);
      expect(KerabieMessage.fromServer(serverMessage(1, 'a')).status, KerabieMessageStatus.sent);
    });

    test('replies that arrived while the app was away count as unread after a reconnect', () async {
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Hello')],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      realtime.emit('ready', {'conversationId': 7, 'agentsOnline': true});

      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Hello'), serverMessage(2, 'Missed one'), serverMessage(3, 'Missed two')],
      };
      realtime.emit('ready', {'conversationId': 7, 'agentsOnline': true});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.unreadCount, 2);
      c.dispose();
    });

    test('the conversation list comes from the server', () async {
      server.routes['GET /public/widget/conversations'] = {
        'conversations': [
          {'id': 7, 'name': 'Ada', 'lastMessage': 'Thanks', 'lastMessageTime': '2026-10-19T09:00:00Z', 'unreadCount': 2, 'isOnline': true, 'status': 'ACTIVE'},
          {'bad': true},
        ],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      expect(c.hasChatted, isFalse);

      await c.refreshConversations();

      expect(c.conversations.single.name, 'Ada');
      expect(c.conversations.single.unreadCount, 2);
      expect(c.conversations.single.status, 'active');
      expect(c.hasChatted, isTrue);
      c.dispose();
    });
  });

  group('screens', () {
    test('trackScreen reports the page, the one before it and how long the visitor stayed', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      c.trackScreen('checkout');
      c.trackScreen('/checkout'); // same screen again
      c.trackScreen('/orders/12');

      expect(realtime.pages.map((p) => (p.path, p.previous)), [('/checkout', null), ('/orders/12', '/checkout')]);
      expect(realtime.pageExits, ['/checkout']);
      expect(c.screen, '/orders/12');
      c.dispose();
    });

    test('the current screen is reported again after the connection comes back', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      c.trackScreen('/home');
      realtime.pages.clear();

      realtime.emit('connect');
      expect(realtime.pages.single.path, '/home');
      c.dispose();
    });

    test('screen paths always start with a slash', () {
      expect(kerabieScreenPath('home'), '/home');
      expect(kerabieScreenPath('/home'), '/home');
      expect(kerabieScreenPath('  '), '/');
    });
  });

  group('attachments', () {
    late FakeFilePicker picker;
    late Directory dir;
    late File photo;
    var polls = 0;

    setUp(() async {
      polls = 0;
      dir = await Directory.systemTemp.createTemp('kerabie_test');
      photo = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
      picker = FakeFilePicker();
      server.routes['POST /public/widget/attachment'] = (http.Request r) {
        expect(r.headers['content-type'], startsWith('multipart/form-data'));
        return json({'jobId': 'job1'});
      };
      server.routes['GET /public/widget/attachment/job1'] = (http.Request r) {
        polls++;
        return polls < 2
            ? json({'status': 'processing'})
            : json({'status': 'succeeded', 'result': {'key': 'chat/abc.jpg', 'fileName': 'photo.jpg', 'mimeType': 'image/jpeg'}});
      };
    });

    tearDown(() => dir.delete(recursive: true));

    test('a picked photo uploads in the background and goes out with the caption', () async {
      picker.image = KerabiePickedFile(path: photo.path, name: 'photo.jpg', mimeType: 'image/jpeg', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      await c.pickPhoto();
      expect(c.staging.pending!.name, 'photo.jpg');
      expect(c.staging.isUploading, isFalse);
      expect(c.staging.uploaded!.key, 'chat/abc.jpg');

      await c.sendMessage('My receipt');

      expect(realtime.sent.single.type, 'image');
      expect(realtime.sent.single.key, 'chat/abc.jpg');
      expect(realtime.sent.single.fileName, 'photo.jpg');
      expect(realtime.sent.single.body, 'My receipt');
      final shown = c.messages.single;
      expect(shown.type, 'image');
      expect(shown.attachmentUrl, photo.path); // the local file, until the server copy replaces it
      expect(c.staging.pending, isNull);
      c.dispose();
    });

    test('a photo can go without a caption', () async {
      picker.image = KerabiePickedFile(path: photo.path, name: 'photo.jpg', mimeType: 'image/jpeg', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();
      await c.pickPhoto();

      await c.sendMessage('');
      expect(realtime.sent.single.body, '');
      expect(realtime.sent.single.type, 'image');
      c.dispose();
    });

    test('sending waits while the file is still uploading', () async {
      picker.document = KerabiePickedFile(path: photo.path, name: 'doc.pdf', mimeType: 'application/pdf', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      final picking = c.pickDocument();
      await Future<void>.delayed(Duration.zero);
      expect(c.staging.isUploading, isTrue);
      await c.sendMessage('now');
      expect(realtime.sent, isEmpty);

      await picking;
      expect(c.staging.uploaded, isNotNull);
      c.dispose();
    });

    test('a file over 25 MB is refused with a clear message, and nothing is uploaded', () async {
      picker.document = KerabiePickedFile(path: photo.path, name: 'big.pdf', mimeType: 'application/pdf', size: 26 * 1024 * 1024);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      await c.pickDocument();
      expect(c.staging.error, contains('too large'));
      expect(c.staging.pending, isNull);
      expect(server.last('POST', '/public/widget/attachment'), isNull);
      c.dispose();
    });

    test('a file type the server does not accept is refused', () async {
      picker.document = KerabiePickedFile(path: photo.path, name: 'run.exe', mimeType: 'application/x-msdownload', size: 10);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      await c.pickDocument();
      expect(c.staging.error, 'File type "application/x-msdownload" is not allowed');
      c.dispose();
    });

    test('a failed upload shows the server message and clears the picked file', () async {
      server.routes['GET /public/widget/attachment/job1'] = (http.Request r) => json({'status': 'failed', 'error': 'Virus found'});
      picker.image = KerabiePickedFile(path: photo.path, name: 'photo.jpg', mimeType: 'image/jpeg', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      await c.pickPhoto();
      expect(c.staging.error, 'Virus found');
      expect(c.staging.pending, isNull);
      expect(c.staging.isUploading, isFalse);
      c.dispose();
    });

    test('cancelling the picker changes nothing', () async {
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();
      await c.pickPhoto();
      expect(c.staging.pending, isNull);
      expect(c.staging.error, isNull);
      c.dispose();
    });

    test('removing the file while it uploads stops it from being sent', () async {
      picker.image = KerabiePickedFile(path: photo.path, name: 'photo.jpg', mimeType: 'image/jpeg', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();

      final picking = c.pickPhoto();
      await Future<void>.delayed(Duration.zero);
      expect(c.staging.isUploading, isTrue);
      c.staging.remove();
      await picking;

      expect(c.staging.pending, isNull);
      expect(c.staging.uploaded, isNull);
      await c.sendMessage('');
      expect(realtime.sent, isEmpty);
      c.dispose();
    });

    test('a failed attachment message is sent again with its file', () async {
      picker.image = KerabiePickedFile(path: photo.path, name: 'photo.jpg', mimeType: 'image/jpeg', size: 3);
      final c = makeController(realtime: realtime, server: server, filePicker: picker);
      await c.start();
      await c.pickPhoto();
      realtime.connected = false;
      await c.sendMessage('caption');
      expect(c.messages.single.status, KerabieMessageStatus.failed);

      realtime.connected = true;
      await c.retry(c.messages.single);
      expect(realtime.sent.single.key, 'chat/abc.jpg');
      expect(realtime.sent.single.body, 'caption');
      c.dispose();
    });

    test('the upload error goes away by itself', () async {
      final staging = KerabieAttachmentStaging(errorDuration: const Duration(milliseconds: 20));
      staging.showError('Oops');
      expect(staging.error, 'Oops');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(staging.error, isNull);
      staging.dispose();
    });
  });
}
