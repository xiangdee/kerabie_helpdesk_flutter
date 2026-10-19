// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Builds the palette the chat would use for [config], with the dashboard answering [settings].
Future<KerabiePalette> paletteFor(
  WidgetTester tester, {
  KerabieConfig config = sampleConfig,
  Map<String, dynamic> settings = const {},
  Brightness device = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final server = FakeServer({
    'GET /public/widget/init': {'orgId': 1, 'settings': settings},
    'GET /public/widget/messages': {'conversationId': null, 'messages': []},
  });
  final controller = makeController(realtime: FakeRealtime(), server: server, config: config);
  await tester.runAsync(controller.start);
  addTearDown(controller.dispose);

  late KerabiePalette palette;
  tester.platformDispatcher.platformBrightnessTestValue = device;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      palette = KerabiePalette.of(context, controller);
      return const SizedBox();
    }),
  ));
  return palette;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const light = Color(0xFFFFFFFF);
  const dark = Color(0xFF1E2530);

  group('KerabieSettings.fromServer theme', () {
    test('reads the dashboard Theme setting and defaults to light', () {
      expect(KerabieSettings.fromServer({'theme': 'dark'}).mode, KerabieThemeMode.dark);
      expect(KerabieSettings.fromServer({'theme': 'auto'}).mode, KerabieThemeMode.auto);
      expect(KerabieSettings.fromServer({'theme': 'light'}).mode, KerabieThemeMode.light);
      expect(KerabieSettings.fromServer({}).mode, KerabieThemeMode.light);
      expect(KerabieSettings.fromServer({'theme': 'something'}).mode, KerabieThemeMode.light);
    });
  });

  group('light and dark mode', () {
    testWidgets('stays light on a dark device when the dashboard says light', (tester) async {
      final p = await paletteFor(tester, settings: {'theme': 'light'}, device: Brightness.dark);
      expect(p.background, light);
    });

    testWidgets('follows the dashboard when it says dark', (tester) async {
      final p = await paletteFor(tester, settings: {'theme': 'dark'}, device: Brightness.light);
      expect(p.background, dark);
    });

    testWidgets('auto follows the device', (tester) async {
      expect((await paletteFor(tester, settings: {'theme': 'auto'}, device: Brightness.dark)).background, dark);
      expect((await paletteFor(tester, settings: {'theme': 'auto'}, device: Brightness.light)).background, light);
    });

    testWidgets('the developer mode wins over the dashboard', (tester) async {
      final p = await paletteFor(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'Test app',
          appVersion: '1.0.0',
          theme: KerabieTheme(mode: KerabieThemeMode.dark),
        ),
        settings: {'theme': 'light'},
      );
      expect(p.background, dark);
    });
  });

  group('colour overrides', () {
    testWidgets('text on the visitor bubble follows the bubble colour, not the header', (tester) async {
      final p = await paletteFor(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'Test app',
          appVersion: '1.0.0',
          theme: KerabieTheme(primaryColor: Color(0xFF334155), userBubbleColor: Color(0xFFA3E635)),
        ),
      );
      expect(p.onPrimary, const Color(0xFFFFFFFF));
      expect(p.onUserBubble, const Color(0xFF0F172A));
      expect(p.userBubbleDecoration(BorderRadius.zero).gradient, isNull);
    });

    testWidgets('the visitor bubble and the launcher use the gradient unless a colour is pinned', (tester) async {
      final p = await paletteFor(tester, settings: {'primaryColor': '#2f5f49', 'secondaryColor': '#0f766e'});
      expect(p.userBubbleDecoration(BorderRadius.zero).gradient, isNotNull);
      expect(p.launcherDecoration(const []).gradient, isNotNull);

      final pinned = await paletteFor(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'Test app',
          appVersion: '1.0.0',
          theme: KerabieTheme(bubbleColor: Color(0xFF111111)),
        ),
      );
      expect(pinned.launcherDecoration(const []).gradient, isNull);
      expect(pinned.onLauncher, const Color(0xFFFFFFFF));
    });

    testWidgets('background, text and agent bubble can be replaced', (tester) async {
      final p = await paletteFor(
        tester,
        config: const KerabieConfig(
          widgetKey: 'wk_test',
          appName: 'Test app',
          appVersion: '1.0.0',
          theme: KerabieTheme(
            backgroundColor: Color(0xFFFFF7ED),
            textColor: Color(0xFF431407),
            agentBubbleColor: Color(0xFFFFEDD5),
          ),
        ),
      );
      expect(p.background, const Color(0xFFFFF7ED));
      expect(p.text, const Color(0xFF431407));
      expect(p.agentBubble, const Color(0xFFFFEDD5));
    });
  });
}
