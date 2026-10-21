import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/campaigns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

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
    });
  });

  tearDown(() => realtime.dispose());

  group('knowledge base', () {
    final articles = {
      'data': [
        {'id': 1, 'title': 'Refunds', 'content': '<p>Ask us</p>', 'imageUrl': 'https://cdn/x.png'},
        {'id': 2, 'title': 'Shipping', 'content': '<p>Days</p>', 'imageUrl': null},
        {'nope': true},
      ],
    };

    test('lists the published articles and remembers them for next time', () async {
      server.routes['GET /public/kb/articles'] = articles;
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final kb = KerabieKnowledgeBase(c);
      expect(kb.loading, isTrue);
      await settle();

      expect(kb.loading, isFalse);
      expect(kb.articles.map((a) => a.title), ['Refunds', 'Shipping']);
      expect(kb.articles.first.imageUrl, 'https://cdn/x.png');
      expect(kb.articles.last.imageUrl, isNull);

      final remembered = await c.storage.read<List<dynamic>>('cache:kb:wk_test');
      expect(remembered, hasLength(3));
      kb.dispose();
      c.dispose();
    });

    test('remembered articles show before the server answers, and the server list replaces them', () async {
      final c = makeController(realtime: realtime, server: server);
      await c.storage.write('cache:kb:wk_test', [
        {'id': 9, 'title': 'Old article', 'content': ''},
      ]);
      server.routes['GET /public/kb/articles'] = (http.Request r) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return json(articles);
      };
      await c.start();
      final kb = KerabieKnowledgeBase(c);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(kb.articles.single.title, 'Old article');
      expect(kb.loading, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(kb.articles.map((a) => a.title), ['Refunds', 'Shipping']);
      kb.dispose();
      c.dispose();
    });

    test('searching waits for the visitor to stop typing, then sends one request', () async {
      server.routes['GET /public/kb/articles'] = articles;
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final kb = KerabieKnowledgeBase(c, searchDelay: const Duration(milliseconds: 30));
      await settle();
      final before = server.requests.where((r) => r.url.path == '/public/kb/articles').length;

      kb.search('r');
      kb.search('re');
      kb.search('refund');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final searches = server.requests.where((r) => r.url.path == '/public/kb/articles' && r.url.queryParameters.containsKey('search'));
      expect(searches.map((r) => r.url.queryParameters['search']), ['refund']);
      expect(server.requests.where((r) => r.url.path == '/public/kb/articles').length, before + 1);
      kb.dispose();
      c.dispose();
    });

    test('a search does not overwrite the remembered default list', () async {
      server.routes['GET /public/kb/articles'] = articles;
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final kb = KerabieKnowledgeBase(c);
      await settle();

      server.routes['GET /public/kb/articles'] = {
        'data': [
          {'id': 5, 'title': 'Only match', 'content': ''},
        ],
      };
      await kb.refetch('match');
      expect(kb.articles.single.title, 'Only match');
      expect(await c.storage.read<List<dynamic>>('cache:kb:wk_test'), hasLength(3));
      kb.dispose();
      c.dispose();
    });

    test('keeps the articles it has when the server fails', () async {
      server.routes['GET /public/kb/articles'] = articles;
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final kb = KerabieKnowledgeBase(c);
      await settle();

      server.routes['GET /public/kb/articles'] = (http.Request r) => json({'message': 'down'}, 500);
      await kb.refetch();
      expect(kb.articles, hasLength(2));
      expect(kb.loading, isFalse);
      kb.dispose();
      c.dispose();
    });

    test('one article is fetched with its full body, or null when it is missing', () async {
      server.routes['GET /public/kb/articles'] = articles;
      server.routes['GET /public/kb/articles/1'] = {
        'article': {'id': 1, 'title': 'Refunds', 'content': '<p>Full</p>', 'imageUrl': null},
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();

      expect((await KerabieKnowledgeBase.fetchArticle(c, 1))!.content, '<p>Full</p>');
      expect(await KerabieKnowledgeBase.fetchArticle(c, 404), isNull);
      c.dispose();
    });

    test('a vote is sent once, remembered, and a rate limit counts as done', () async {
      server.routes['POST /public/kb/articles/1/feedback'] = {'success': true};
      server.routes['POST /public/kb/articles/2/feedback'] = (http.Request r) => json({'message': 'Too many requests'}, 429);
      server.routes['POST /public/kb/articles/3/feedback'] = (http.Request r) => json({'message': 'boom'}, 500);
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final feedback = KerabieArticleFeedback(c);

      expect(await feedback.previousVote(1), isNull);
      expect(await feedback.vote(1, helpful: false), isTrue);
      expect(jsonDecode(server.last('POST', '/public/kb/articles/1/feedback')!.body), {'helpful': false});
      expect(await feedback.previousVote(1), isFalse);

      expect(await feedback.vote(2, helpful: true), isTrue);
      expect(await feedback.previousVote(2), isNull);

      expect(await feedback.vote(3, helpful: true), isFalse);
      c.dispose();
    });
  });

  group('tickets', () {
    final ticketRow = {'id': 12, 'subject': 'Late order', 'status': 'ACTIVE', 'priority': 'HIGH', 'createdAt': '2026-10-19T09:00:00Z'};

    test('lists the visitor\'s tickets', () async {
      server.routes['GET /public/tickets'] = {
        'data': [ticketRow, {'id': 13, 'status': 'CLOSED', 'priority': 'weird', 'createdAt': 'not a date'}],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final tickets = KerabieTickets(c);
      expect(tickets.loading, isTrue);
      await settle();

      expect(tickets.loading, isFalse);
      expect(tickets.tickets.map((t) => t.id), [12, 13]);
      expect(tickets.tickets.first.priority, KerabieTicketPriority.high);
      expect(tickets.tickets.last.priority, KerabieTicketPriority.normal);
      expect(tickets.tickets.last.isClosed, isTrue);
      expect(tickets.tickets.last.subject, isNull);
      tickets.dispose();
      c.dispose();
    });

    test('opens a ticket with its messages', () async {
      server.routes['GET /public/tickets'] = {'data': []};
      server.routes['GET /public/tickets/12'] = {
        'ticket': ticketRow,
        'messages': [
          {'id': 1, 'body': 'Where is it?', 'senderRole': 'customer', 'createdAt': '2026-10-19T09:00:00Z'},
          {'id': 2, 'body': 'On its way', 'senderRole': 'agent', 'senderName': 'Sam', 'createdAt': '2026-10-19T09:05:00Z'},
        ],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final tickets = KerabieTickets(c);

      final thread = (await tickets.getTicket(12))!;
      expect(thread.ticket.subject, 'Late order');
      expect(thread.messages.map((m) => m.fromCustomer), [true, false]);
      expect(thread.messages.last.senderName, 'Sam');
      expect(await tickets.getTicket(99), isNull);
      tickets.dispose();
      c.dispose();
    });

    test('creating a ticket sends the priority in capitals and refreshes the list', () async {
      server.routes['GET /public/tickets'] = {'data': []};
      server.routes['POST /public/tickets'] = {'ticketId': 55};
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final tickets = KerabieTickets(c);
      await settle();
      final lists = server.requests.where((r) => r.method == 'GET' && r.url.path == '/public/tickets').length;

      final id = await tickets.createTicket(subject: 'Help', message: 'It broke', priority: KerabieTicketPriority.urgent, email: 'a@b.co');
      await settle();

      expect(id, 55);
      expect(jsonDecode(server.last('POST', '/public/tickets')!.body), {'subject': 'Help', 'message': 'It broke', 'priority': 'URGENT', 'email': 'a@b.co'});
      expect(server.requests.where((r) => r.method == 'GET' && r.url.path == '/public/tickets').length, lists + 1);
      tickets.dispose();
      c.dispose();
    });

    test('a ticket that cannot be created gives null, and a reply says whether it went', () async {
      server.routes['GET /public/tickets'] = {'data': []};
      server.routes['POST /public/tickets'] = (http.Request r) => json({'message': 'Plan limit'}, 403);
      server.routes['POST /public/tickets/12/reply'] = {'success': true};
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final tickets = KerabieTickets(c);

      expect(await tickets.createTicket(subject: 's', message: 'm'), isNull);
      expect(await tickets.reply(12, 'thanks'), isTrue);
      expect(jsonDecode(server.last('POST', '/public/tickets/12/reply')!.body), {'body': 'thanks'});
      expect(await tickets.reply(13, 'thanks'), isFalse);
      tickets.dispose();
      c.dispose();
    });

    test('the status pill and the time ago read like the other SDKs', () {
      expect(kerabieTicketStatusStyle('RESOLVED').label, 'Resolved');
      expect(kerabieTicketStatusStyle('closed').label, 'Closed');
      expect(kerabieTicketStatusStyle('IN_PROGRESS').label, 'In progress');
      expect(kerabieTicketStatusStyle('PENDING').label, 'In progress');
      expect(kerabieTicketStatusStyle('ACTIVE').label, 'Open');
      expect(kerabieTicketStatusStyle('WAITING').label, 'Open');

      final now = DateTime(2026, 10, 19, 12);
      expect(kerabieAgo(now.subtract(const Duration(seconds: 10)), now: now), 'just now');
      expect(kerabieAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(kerabieAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(kerabieAgo(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(kerabieAgo(now.add(const Duration(hours: 1)), now: now), 'just now'); // a clock that is ahead
      expect(kerabieAgo(null), '');
    });
  });

  group('store', () {
    test('lists products and builds the storefront address from the slug', () async {
      server.routes['GET /public/store/by-widget'] = {
        'store': {'name': 'Acme Shop', 'slug': 'acme'},
        'products': [
          {'id': 1, 'name': 'Sneakers', 'price': 45.5, 'currency': 'USD', 'imageUrl': ''},
          {'id': 2, 'name': 'Odd', 'price': 10, 'currency': 'NOPE'},
        ],
      };
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final store = KerabieStore(c);
      await settle();

      expect(store.storeName, 'Acme Shop');
      expect(store.storeUrl, 'https://acme.kerabie.com');
      expect(store.products.first.formattedPrice, r'$45.50');
      expect(store.products.first.imageUrl, isNull);
      expect(store.products.last.formattedPrice, isNotEmpty); // an unknown currency still shows a price
      store.dispose();
      c.dispose();
    });

    test('a store without a slug has no address, and a server error keeps the list empty', () async {
      server.routes['GET /public/store/by-widget'] = {'store': {'name': 'No slug'}, 'products': []};
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final store = KerabieStore(c);
      await settle();
      expect(store.storeUrl, isNull);
      expect(store.loading, isFalse);

      server.routes['GET /public/store/by-widget'] = (http.Request r) => json({'message': 'x'}, 500);
      await store.refetch();
      expect(store.products, isEmpty);
      store.dispose();
      c.dispose();
    });
  });

  group('campaign rules', () {
    test('screens match with wildcards, ignoring case, query strings and trailing slashes', () {
      expect(kerabieMatchesScreen(null, null), isTrue);
      expect(kerabieMatchesScreen('', '/anything'), isTrue);
      expect(kerabieMatchesScreen('/checkout', null), isFalse); // the app never said where the user is
      expect(kerabieMatchesScreen('/checkout', '/Checkout/?step=2'), isTrue);
      expect(kerabieMatchesScreen('/orders/*', '/orders/12'), isTrue);
      expect(kerabieMatchesScreen('/orders/*', '/profile'), isFalse);
      expect(kerabieMatchesScreen('/a, /b', '/b'), isTrue);
      expect(kerabieMatchesScreen('orders', '/orders'), isTrue);
      expect(kerabieMatchesScreen('/a.b', '/axb'), isFalse); // a dot in a pattern is a dot
    });

    KerabieEligibility ctx({bool returning = false, bool hasChatted = false, DateTime? lastShown, bool launch = false, String? screen}) =>
        KerabieEligibility(screen: screen, now: DateTime(2026, 10, 19, 12), returning: returning, hasChatted: hasChatted, lastShownAt: lastShown, shownThisLaunch: launch);

    test('website only triggers never show in an app', () {
      expect(kerabieIsEligible(const KerabieCampaign(id: 1, name: '', message: '', trigger: 'scroll_depth'), ctx()), isFalse);
      expect(kerabieIsEligible(const KerabieCampaign(id: 1, name: '', message: '', trigger: 'exit_intent'), ctx()), isFalse);
      expect(kerabieIsEligible(const KerabieCampaign(id: 1, name: '', message: '', trigger: 'time_on_page'), ctx()), isTrue);
    });

    test('audiences', () {
      KerabieCampaign audience(String a) => KerabieCampaign(id: 1, name: '', message: '', audience: a);
      expect(kerabieIsEligible(audience('new'), ctx()), isTrue);
      expect(kerabieIsEligible(audience('new'), ctx(returning: true)), isFalse);
      expect(kerabieIsEligible(audience('returning'), ctx()), isFalse);
      expect(kerabieIsEligible(audience('returning'), ctx(returning: true)), isTrue);
      expect(kerabieIsEligible(audience('not_chatted'), ctx(hasChatted: true)), isFalse);
      expect(kerabieIsEligible(audience('not_chatted'), ctx()), isTrue);
      expect(kerabieIsEligible(audience('country'), ctx()), isTrue); // the server already decided
    });

    test('frequency', () {
      KerabieCampaign every(String f) => KerabieCampaign(id: 1, name: '', message: '', frequency: f);
      final yesterday = DateTime(2026, 10, 18, 11);
      final today = DateTime(2026, 10, 19, 6);
      expect(kerabieIsEligible(every('once_per_visitor'), ctx()), isTrue);
      expect(kerabieIsEligible(every('once_per_visitor'), ctx(lastShown: yesterday)), isFalse);
      expect(kerabieIsEligible(every('once_per_day'), ctx(lastShown: yesterday)), isTrue);
      expect(kerabieIsEligible(every('once_per_day'), ctx(lastShown: today)), isFalse);
      expect(kerabieIsEligible(every('every_session'), ctx(lastShown: today)), isTrue);
      expect(kerabieIsEligible(every('every_session'), ctx(launch: true)), isFalse);
    });

    test('the pages rule uses the current screen', () {
      const c = KerabieCampaign(id: 1, name: '', message: '', pages: '/checkout');
      expect(kerabieIsEligible(c, ctx(screen: '/checkout')), isTrue);
      expect(kerabieIsEligible(c, ctx(screen: '/home')), isFalse);
      expect(kerabieIsEligible(c, ctx()), isFalse);
    });
  });

  group('campaigns in the app', () {
    List<Map<String, dynamic>> events() => server.requests
        .where((r) => r.method == 'POST' && r.url.path.contains('/public/campaigns/'))
        .map((r) => {'id': r.url.pathSegments[2], ...jsonDecode(r.body) as Map<String, dynamic>})
        .toList();

    void serve(List<Map<String, dynamic>> campaigns) {
      server.routes['GET /public/campaigns'] = {'campaigns': campaigns};
      server.routes['POST /public/campaigns/1/events'] = {'ok': true};
      server.routes['POST /public/campaigns/2/events'] = {'ok': true};
    }

    Map<String, dynamic> campaign(int id, {String trigger = 'page_load', String? pages, String frequency = 'once_per_visitor', String audience = 'all', String? ctaLabel}) => {
          'id': id,
          'name': 'Promo $id',
          'message': 'Hello $id',
          'trigger': trigger,
          'triggerValue': '0',
          'pages': pages,
          'frequency': frequency,
          'audience': audience,
          'ctaLabel': ctaLabel,
          'ctaAction': 'open_chat',
        };

    Future<(KerabieController, KerabieCampaigns)> start({Duration delay = const Duration(milliseconds: 10)}) async {
      final c = makeController(realtime: realtime, server: server);
      await c.start();
      final campaigns = KerabieCampaigns(c, pageLoadDelay: delay, autoHide: const Duration(milliseconds: 200));
      return (c, campaigns);
    }

    test('a page load campaign shows after the delay and is reported as shown', () async {
      serve([campaign(1)]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(campaigns.current!.id, 1);
      expect(events(), [
        {'id': '1', 'widgetKey': 'wk_test', 'event': 'shown'},
      ]);
      campaigns.dispose();
      c.dispose();
    });

    test('a campaign for certain screens waits for the app to say it is on one of them', () async {
      serve([campaign(1, pages: '/checkout')]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNull);

      c.trackScreen('/checkout');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current!.id, 1);
      campaigns.dispose();
      c.dispose();
    });

    test('a time on page campaign shows without any screen change', () async {
      serve([campaign(1, trigger: 'time_on_page')]);
      final (c, campaigns) = await start(delay: const Duration(seconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current!.id, 1);
      campaigns.dispose();
      c.dispose();
    });

    test('nothing pops up while the chat is open, and it shows once the chat closes', () async {
      serve([campaign(1)]);
      final (c, campaigns) = await start();
      c.open();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNull);
      expect(events(), isEmpty);
      campaigns.dispose();
      c.dispose();
    });

    test('it hides by itself after a while', () async {
      serve([campaign(1)]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(campaigns.current, isNull);
      campaigns.dispose();
      c.dispose();
    });

    test('opening it counts as opened, and the first message after counts as a reply, once', () async {
      serve([campaign(1, ctaLabel: 'Chat')]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      campaigns.engage(withClick: true);
      expect(campaigns.current, isNull);
      await c.sendMessage('Hi');
      await c.sendMessage('Hi again');
      await settle();

      expect(events().map((e) => e['event']), ['shown', 'opened', 'clicked', 'replied']);
      campaigns.dispose();
      c.dispose();
    });

    test('dismissing it counts nothing more than shown', () async {
      serve([campaign(1)]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      campaigns.dismiss();
      await c.sendMessage('Hi');
      await settle();

      expect(events().map((e) => e['event']), ['shown']);
      campaigns.dispose();
      c.dispose();
    });

    test('once per visitor is remembered across launches', () async {
      serve([campaign(1)]);
      var (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNotNull);
      campaigns.dispose();
      c.dispose();

      realtime = FakeRealtime();
      (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNull);
      campaigns.dispose();
      c.dispose();
    });

    test('the new and returning audiences follow the app launches', () async {
      serve([campaign(1, audience: 'new'), campaign(2, audience: 'returning')]);
      var (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current!.id, 1); // first launch: new
      campaigns.dispose();
      c.dispose();

      SharedPreferences.setMockInitialValues({
        'kerabie:sdk:has_visited': '1',
      });
      realtime = FakeRealtime();
      (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current!.id, 2); // later launch: returning
      campaigns.dispose();
      c.dispose();
    });

    test('a visitor who already chatted does not get a campaign meant for people who have not', () async {
      server.routes['GET /public/widget/messages'] = {
        'conversationId': 7,
        'messages': [serverMessage(1, 'Hello', role: 'customer')],
      };
      serve([campaign(1, audience: 'not_chatted')]);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNull);
      campaigns.dispose();
      c.dispose();
    });

    test('a campaign list that cannot be loaded shows nothing and breaks nothing', () async {
      server.routes['GET /public/campaigns'] = (http.Request r) => json({'message': 'down'}, 500);
      final (c, campaigns) = await start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(campaigns.current, isNull);
      campaigns.dispose();
      c.dispose();
    });
  });
}
