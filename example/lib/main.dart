import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

/// Run with your own key:
///   flutter run --dart-define=KERABIE_WIDGET_KEY=wk_yourorg_123
const widgetKey = String.fromEnvironment('KERABIE_WIDGET_KEY');

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    KerabieProvider(
      // Share the key with MaterialApp so a notification tap, a link or a campaign can open the chat from anywhere.
      navigatorKey: navigatorKey,
      config: const KerabieConfig(
        widgetKey: widgetKey,
        appName: 'Kerabie example',
        appVersion: '1.0.0',
        user: KerabieUser(name: 'Example user', email: 'user@example.com'),
        deepLinkScheme: 'kerabieexample',
      ),
      // A campaign button can open the help centre.
      onOpenKnowledgeBase: () => navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => const KerabieKnowledgeBaseScreen())),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        // Tells Kerabie which screen the customer is on, from the route names.
        navigatorObservers: [KerabieNavigatorObserver()],
        title: 'Kerabie example',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2F5F49), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF2F5F49), brightness: Brightness.dark, useMaterial3: true),
        initialRoute: '/',
        routes: {
          '/': (_) => const HomeScreen(),
          '/orders/1042': (_) => const OrderScreen(),
        },
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kerabie = KerabieProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kerabie example')),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widgetKey.isEmpty ? 'Run with --dart-define=KERABIE_WIDGET_KEY=wk_...' : 'Connected: ${kerabie.isConnected}'),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => KerabieChat.show(context), child: const Text('Chat with us')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/orders/1042'),
                  child: const Text('My order'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KerabieKnowledgeBaseScreen())),
                  child: const Text('Help centre'),
                ),
                if (kerabie.settings.ticketsEnabled)
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KerabieTicketsScreen())),
                    child: const Text('My tickets'),
                  ),
              ],
            ),
          ),
          // The floating button, or the search bar, whichever the dashboard picked.
          const KerabieLauncher(),
        ],
      ),
    );
  }
}

class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order #1042')),
      body: Center(
        child: FilledButton(
          // The agent sees what the customer was looking at.
          onPressed: () => KerabieProvider.of(context, listen: false).openWithContext(
            const KerabieChatContext(type: 'order', id: '1042', title: 'Order #1042', data: {'status': 'shipped'}),
          ),
          child: const Text('Get help with this order'),
        ),
      ),
    );
  }
}
