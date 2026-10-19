import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

/// Run with your own key:
///   flutter run --dart-define=KERABIE_WIDGET_KEY=wk_yourorg_123
const widgetKey = String.fromEnvironment('KERABIE_WIDGET_KEY');

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    KerabieProvider(
      // Share the key with MaterialApp so a notification tap or a link can open the chat from anywhere.
      navigatorKey: navigatorKey,
      config: const KerabieConfig(
        widgetKey: widgetKey,
        appName: 'Kerabie example',
        appVersion: '1.0.0',
        user: KerabieUser(name: 'Example user', email: 'user@example.com'),
        deepLinkScheme: 'kerabieexample',
      ),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Kerabie example',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2F5F49), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF2F5F49), brightness: Brightness.dark, useMaterial3: true),
        home: const HomeScreen(),
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
              ],
            ),
          ),
          const KerabieLauncher(),
        ],
      ),
    );
  }
}
