# kerabie_helpdesk_flutter

Embed the [Kerabie](https://kerabie.com) help desk in a Flutter app. A provider, a launcher and a real-time chat screen.

- Real-time chat that lands in your Kerabie inbox
- Chat history, typing indicators, unread count and AI replies that stream in word by word
- Colours, widget name, welcome message, launcher icon, AI assistant picture and branding follow **Settings, Widget** in the dashboard
- Light and dark mode from the dashboard's Theme setting, with text colours picked by luminance so they stay readable on any brand colour
- Push token registration, and opening the chat from a tapped notification or a link

Requires Flutter 3.27 or later and Dart 3.6 or later. Android and iOS.

## Install

```bash
flutter pub add kerabie_helpdesk_flutter
```

Get your widget key (it starts with `wk_`) from **Settings, Widget** in the Kerabie dashboard.

## Quick start

Put `KerabieProvider` above your `MaterialApp`, give both the same navigator key, and add the launcher.

```dart
import 'package:flutter/material.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    KerabieProvider(
      navigatorKey: navigatorKey,
      config: const KerabieConfig(
        widgetKey: 'wk_yourorg_123',
        appName: 'My App',
        appVersion: '1.0.0',
        user: KerabieUser(name: 'Jane', email: 'jane@example.com'),
      ),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: Stack(children: [HomeScreen(), KerabieLauncher()]),
        ),
      ),
    ),
  );
}
```

To open the chat from your own button:

```dart
ElevatedButton(onPressed: () => KerabieChat.show(context), child: const Text('Chat with us'));
```

## Configuration

`KerabieConfig`:

| Field | Required | Description |
|---|---|---|
| `widgetKey` | Yes | Your widget key |
| `appName`, `appVersion` | Yes | Shown to agents, so they know which app the customer is on |
| `appBuild` | No | Build number, shown to agents |
| `user` | No | A `KerabieUser`: `id`, `name`, `email`, `phone`, `customAttributes` |
| `theme` | No | A `KerabieTheme`: `primaryColor`, `secondaryColor`, `gradient`, `cornerRadius`, `mode` (`light`, `dark` or `auto`), `backgroundColor`, `textColor`, `agentBubbleColor`, `userBubbleColor`, `bubbleColor`. Overrides the dashboard |
| `deepLinkScheme` | No | Your app's URL scheme. When set, only `myapp://conversation/123` links open the chat |
| `baseUrl` | No | Only for a self-hosted or staging backend |

## Chat state

```dart
final kerabie = KerabieProvider.of(context); // rebuilds when the chat changes
```

| Member | Description |
|---|---|
| `messages` | The conversation, oldest first |
| `unreadCount` | Replies that arrived while the chat was closed |
| `isConnected` | Whether the live connection is up |
| `isTyping`, `isAiTyping` | An agent, or the AI assistant, is writing |
| `agentsOnline` | How many agents are online, once the server has said |
| `settings` | What the dashboard has saved for this widget |
| `sendMessage(text)`, `retry(message)` | Send, and resend a failed message |
| `identify(user)` | Tell Kerabie who the customer is |

## Push notifications

Kerabie keeps one push token per customer, so use one push service in your app. This package does not depend on a push package: you get the token from your service and pass it in, with the provider that issued it. The providers are `fcm` (a Firebase Cloud Messaging token, which also covers iOS through Firebase) and `expo`. For `fcm`, connect your Firebase project once in the dashboard under Settings, Integrations, App push, so Kerabie can send to your app's customers.

```dart
final kerabie = KerabieProvider.of(context, listen: false);
await kerabie.registerPushToken(token, provider: KerabiePushProvider.fcm);
```

Kerabie notifications carry `conversationId` and `orgId` in their data. When the user taps one, pass the data in. With Firebase Cloud Messaging, handle both cases FCM documents: the tap that launches the app, and the tap from the background.

```dart
final messaging = FirebaseMessaging.instance;

final initial = await messaging.getInitialMessage();
if (initial != null) kerabie.handleNotificationData(initial.data);

FirebaseMessaging.onMessageOpenedApp.listen((m) => kerabie.handleNotificationData(m.data));
messaging.onTokenRefresh.listen((t) => kerabie.registerPushToken(t, provider: KerabiePushProvider.fcm));
```

The chat can only open from a tap when `KerabieProvider` has the same `navigatorKey` as your `MaterialApp`. With `go_router`, pass the same key as `GoRouter(navigatorKey: navigatorKey)`.

## Opening the chat from a link

Links use the same format in every Kerabie SDK: `<your-scheme>://conversation/<id>`.

Flutter handles incoming deep links itself, so this package does not listen for them. Hand the link over where your app receives it, for example in `onGenerateRoute` or your router's redirect:

```dart
if (kerabie.handleDeepLink(Uri.parse('myapp://conversation/123'))) return;
```

`KerabieDeepLink.conversationUri(123, 'myapp')` builds a link to put in a notification.

## Voice and video calls

Calls are an optional package, so apps that only want chat do not carry the call code: [`kerabie_helpdesk_flutter_calls`](https://pub.dev/packages/kerabie_helpdesk_flutter_calls).

## Not in this version

File attachments, the knowledge base screen, tickets, campaigns and the store.

## Links

- Docs: https://kerabie.com/docs/sdks/flutter
- Kerabie: https://kerabie.com
- MCP server, so an AI assistant can add this SDK for you: https://kerabie.com/sdks/mcp

MIT licensed.
