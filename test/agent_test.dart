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
      'GET /public/widget/messages': {'conversationId': 7, 'messages': []},
    });
  });

  tearDown(() => realtime.dispose());

  Future<KerabieController> started({KerabieAgentOptions? agent}) async {
    final c = makeController(realtime: realtime, server: server)..agent = agent;
    await c.start();
    return c;
  }

  const addToCart = KerabieAgentAction(description: 'Adds an item to the cart in the app', run: _added);

  group('what goes with each message', () {
    test('nothing extra when the app has no agent, so the chat is unchanged', () async {
      final c = await started();
      await c.sendMessage('Hi');
      expect(realtime.agents.single, isNull);
      c.dispose();
    });

    test('the signed-in customer token, the screens and the actions', () async {
      final c = await started(agent: KerabieAgentOptions(getUserToken: () async => 'jwt-abc', screens: {'confirm_action': (_) async => 'yes'}, actions: const {'add_to_cart': addToCart}));
      await c.sendMessage('Add rice to my cart');
      expect(realtime.agents.single, {
        'userToken': 'jwt-abc',
        'uiTools': ['confirm_action'],
        'appActions': [
          {'name': 'add_to_cart', 'description': 'Adds an item to the cart in the app'},
        ],
      });
      c.dispose();
    });

    test('an empty details map, not nothing, when nobody is signed in', () async {
      final c = await started(agent: KerabieAgentOptions(getUserToken: () async => null));
      await c.sendMessage('Hi');
      expect(realtime.agents.single, {'uiTools': <String>[]});
      c.dispose();
    });

    test('a token that cannot be read means nobody is signed in, and the message still goes', () async {
      final c = await started(agent: KerabieAgentOptions(getUserToken: () => throw StateError('storage')));
      await c.sendMessage('Hi');
      expect(realtime.sent, hasLength(1));
      expect(realtime.agents.single, isNot(contains('userToken')));
      c.dispose();
    });
  });

  group('when the agent asks the app', () {
    test('shows the screen and sends back what the customer chose', () async {
      Map<String, dynamic>? seen;
      final c = await started(agent: KerabieAgentOptions(screens: {
        'confirm_action': (args) async {
          seen = args;
          return 'yes';
        },
      }));
      realtime.emit('agent_request', {'requestId': 'r1', 'kind': 'ui', 'name': 'confirm_action', 'args': {'summary': 'Pickup 3 pm'}});
      await Future<void>.delayed(Duration.zero);
      expect(seen, {'summary': 'Pickup 3 pm'});
      expect(realtime.answers.single, (requestId: 'r1', result: 'yes', error: null));
      c.dispose();
    });

    test('runs an action with its arguments and sends back its result', () async {
      final c = await started(agent: KerabieAgentOptions(actions: {
        'add_to_cart': KerabieAgentAction(description: 'Adds an item to the cart in the app', run: (args) async => 'Added ${args['quantity']} to the cart'),
      }));
      realtime.emit('agent_request', {'requestId': 'r2', 'kind': 'action', 'name': 'add_to_cart', 'args': {'quantity': 2}});
      await Future<void>.delayed(Duration.zero);
      expect(realtime.answers.single.result, 'Added 2 to the cart');
      c.dispose();
    });

    test('says it failed when the handler throws, and when the screen or action is not registered', () async {
      final c = await started(agent: KerabieAgentOptions(screens: {'confirm_action': (_) async => throw StateError('closed')}));
      realtime.emit('agent_request', {'requestId': 'a', 'kind': 'ui', 'name': 'confirm_action'});
      realtime.emit('agent_request', {'requestId': 'b', 'kind': 'ui', 'name': 'pick_schedule'});
      realtime.emit('agent_request', {'requestId': 'c', 'kind': 'action', 'name': 'format_disk'});
      await Future<void>.delayed(Duration.zero);
      // Independent requests may answer in any order.
      expect(realtime.answers.map((a) => a.requestId).toSet(), {'a', 'b', 'c'});
      expect(realtime.answers.every((a) => a.error == 'failed' && a.result == null), isTrue);
      c.dispose();
    });

    test('answers failed when the app has no agent at all, and ignores a request without an id', () async {
      final c = await started();
      realtime.emit('agent_request', {'requestId': 'x', 'kind': 'ui', 'name': 'confirm_action'});
      realtime.emit('agent_request', {'kind': 'ui', 'name': 'confirm_action'});
      await Future<void>.delayed(Duration.zero);
      expect(realtime.answers.single, (requestId: 'x', result: null, error: 'failed'));
      c.dispose();
    });
  });
}

Future<String> _added(Map<String, dynamic> args) async => 'Added';
