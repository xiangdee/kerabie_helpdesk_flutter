# kerabie_helpdesk_flutter

Embed the [Kerabie](https://kerabie.com) help desk in a Flutter app: live chat, photos and files, a help centre, tickets, a store, proactive campaigns and a launcher, all following the settings you save in the Kerabie dashboard.

- Real-time chat that lands in your Kerabie inbox, with history, typing indicators, read ticks, unread count and AI replies that stream in word by word
- Photos and files (25 MB), an emoji picker, link previews, and links to the knowledge base articles an AI reply used
- A floating button or a search bar, a settings menu (change name, email or share the transcript, download or erase the customer's data) and a pre-chat form for contact details
- A help centre (searchable knowledge base with article feedback), a store and tickets
- Campaigns: proactive messages from the dashboard, limited to screens, audiences and frequencies
- Open the chat with context (an order, a product, a payment), set or clear the signed-in user, and tell Kerabie which screen the customer is on
- Colours, widget name, welcome message, launcher icon, AI assistant picture and branding follow **Settings, Widget** in the dashboard; light and dark mode with text colours picked by luminance
- Push token registration, and opening the chat from a tapped notification or a link

Requires Flutter 3.27 or later and Dart 3.6 or later. Android and iOS.

## Install

```bash
flutter pub add kerabie_helpdesk_flutter
```

Get your widget key (it starts with `wk_`) from **Settings, Widget** in the Kerabie dashboard.

### Platform setup

On iOS, add the reason for the photo library to `ios/Runner/Info.plist`, so customers can attach photos:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach a photo to your message to support.</string>
```

Android needs nothing extra.

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
        navigatorObservers: [KerabieNavigatorObserver()],
        home: const Scaffold(
          body: Stack(children: [HomeScreen(), KerabieLauncher()]),
        ),
      ),
    ),
  );
}
```

`KerabieLauncher` shows the floating button or the search bar, whichever the dashboard picked. To open the chat from your own button:

```dart
ElevatedButton(onPressed: () => KerabieChat.show(context), child: const Text('Chat with us'));
```

## Configuration

`KerabieConfig`:

| Field | Required | Description |
|---|---|---|
| `widgetKey` | Yes | Your widget key |
| `appName`, `appVersion` | Yes | Your app's name and version, sent when the chat connects |
| `appBuild` | No | Build number, sent with them |
| `user` | No | A `KerabieUser`: `id`, `name`, `email`, `phone`, `role`, `customAttributes` |
| `theme` | No | A `KerabieTheme`: `primaryColor`, `secondaryColor`, `gradient`, `cornerRadius`, `mode` (`light`, `dark` or `auto`), `backgroundColor`, `textColor`, `agentBubbleColor`, `userBubbleColor`, `bubbleColor`, `bubbleIcon`, `bubbleSize`, `bubbleIconSize`, `fontFamily`, `chatbotAvatarUrl`. Overrides the dashboard |
| `chatSettings` | No | A `KerabieChatSettings` that overrides the dashboard: `name`, `welcomeMessage`, `offlineMessage`, `showBranding`, `typingIndicator`, `enableFileAttachments`, `chatbotEnabled`, `layout`, `showMenu`, `launcherType`, `searchbarPlaceholder`, `customerEnrichmentEnabled`, `customerEnrichmentForm` |
| `openMode` | No | `modal` (a full-screen page, the default), `sheet` (a bottom sheet) or `push` (your own navigator opens it, see below) |
| `position` | No | Where the launcher sits: `bottomRight` (default), `bottomLeft`, `topRight`, `topLeft` |
| `defaultOpen` | No | Open the chat as soon as the app has built |
| `hideFloatingButton` | No | Make `KerabieLauncher` draw nothing; open the chat from your own button |
| `deepLinkScheme` | No | Your app's URL scheme. When set, only `myapp://conversation/123` links open the chat |

The welcome message can use `{{name}}`, which becomes the signed-in user's first name (and disappears, with the space before it, when the name is not known).

`KerabieProvider` also takes `onOpenChat`, `onCloseChat`, `onNavigate` (for `push`) and `onOpenKnowledgeBase`.

### Open modes

With `openMode: KerabieOpenMode.push` the SDK does not touch your navigator. It calls `onNavigate`, and your app shows a `KerabieChatScreen`:

```dart
KerabieProvider(
  config: const KerabieConfig(widgetKey: '...', appName: '...', appVersion: '...', openMode: KerabieOpenMode.push),
  onNavigate: (route) => router.push(route.type == KerabieRouteType.conversation ? '/chat/${route.conversationId}' : '/chat'),
  child: ...,
)

// In your /chat route:
KerabieChatScreen(onClose: () => router.pop())
```

Without `onNavigate` the chat opens as a full-screen page.

## Chat state and actions

```dart
final kerabie = KerabieProvider.of(context); // rebuilds when the chat changes
```

| Member | Description |
|---|---|
| `messages` | The conversation, oldest first |
| `unreadCount` | Replies that arrived while the chat was closed |
| `isOpen`, `isConnected` | Whether the chat is on screen, and whether the live connection is up |
| `isTyping`, `isAiTyping` | An agent, or the AI assistant, is writing |
| `agentsOnline` | How many agents are online, once the server has said |
| `settings`, `chat` | What the dashboard saved, and the chat settings in force (the dashboard's with yours on top) |
| `sendMessage(text)`, `retry(message)` | Send, and resend a failed message |
| `showChat()`, `dismissChat()`, `toggle()` | Open and close the chat |
| `currentUser`, `visitorName` | Who the customer is, as far as you have said |
| `setUser(user)`, `clearUser()`, `updateAttribute(key, value)` | See [Who the customer is](#who-the-customer-is) |
| `setAppVersion(version)` | Tell Kerabie the app's version changed; sent with the next connection |
| `openWithContext(context)` | See [Opening the chat with context](#opening-the-chat-with-context) |
| `refreshConversations()`, `conversations` | The customer's conversations |

## Who the customer is

Call `setUser` after login so agents see who they are talking to, `updateAttribute` to add a detail, and `clearUser` after logout. `clearUser` empties the chat on screen and the next visitor starts a fresh anonymous session.

```dart
final kerabie = KerabieProvider.of(context, listen: false);

await kerabie.setUser(const KerabieUser(id: 'u_123', name: 'Ada Obi', email: 'ada@example.com'));
await kerabie.updateAttribute('plan', 'pro');
await kerabie.clearUser();
```

## Opening the chat with context

Tell the agent what the customer was looking at, so they do not have to explain it:

```dart
kerabie.openWithContext(const KerabieChatContext(
  type: 'order', // order, product, transaction, ride, errand, booking or custom
  id: 'ORD-2024-001',
  title: 'Order #2024-001',
  data: {'status': 'shipped', 'total': '45.50'},
));
```

Pass `openChat: false` to only record it and open the chat later.

## Screens

`KerabieNavigatorObserver` tells Kerabie which screen the customer is on, from your routes' names. Agents see the page the customer is on, and campaigns can be limited to certain screens ("On pages" in the dashboard). Dialogs, sheets and routes without a name are ignored. With a router that has no route names, such as `go_router`, report screens yourself:

```dart
kerabie.trackScreen('/checkout');
```

## Launcher

`KerabieLauncher` draws the floating button or the search bar. Use the pieces yourself if you want to place them: `KerabieLauncherButton` and `KerabieSearchBar`. The search bar sends what was typed (and a file picked with its paperclip) to the chat when the customer presses send.

## Help centre, store and tickets

Ready-made screens you can push anywhere in your app. Each one follows your theme and the dashboard settings, and each has a Close button that leaves the route.

```dart
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KerabieKnowledgeBaseScreen()));
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KerabieStoreScreen()));
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KerabieTicketsScreen()));
```

`kerabie.settings.ticketsEnabled` says whether tickets are on in the dashboard, so you can show an entry point only when they are. For your own design use the data classes behind the screens: `KerabieKnowledgeBase`, `KerabieStore` and `KerabieTickets`.

## Campaigns

Proactive messages you create in the dashboard (**Campaigns**) also appear in your app, above the launcher, with their button. They load once per app launch, and need the same `navigatorKey` on `KerabieProvider` and `MaterialApp`.

| Dashboard setting | In the app |
|---|---|
| Trigger **Page load** | Shown about 1.5 seconds after a screen appears (each time the screen changes) |
| Trigger **Time on page** | Shown after N seconds in the app |
| Trigger **Scroll depth**, **Exit intent** | Website only; not shown in apps |
| **On pages** | Matched against the current screen (see [Screens](#screens)). Without a screen, only campaigns for every screen show |
| **Audience** | New and returning mean the first and a later launch on this device; "hasn't chatted" checks this device's conversations; country is decided by the server |
| **Frequency** | Remembered on the device: once per visitor, once per day, or once per app launch |
| Button **Open chat** / **Open a link** | Opens the chat / the link in the browser |
| Button **Open Knowledge Base** | Calls your `onOpenKnowledgeBase`; opens the chat if you do not pass it |

Campaign results (shown, opened, clicked, replied) are counted in the dashboard like they are for the website widget. Nothing pops up while the chat is open.

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

## Links

- Docs: https://kerabie.com/docs/sdks/flutter
- Kerabie: https://kerabie.com
- MCP server, so an AI assistant can add this SDK for you: https://kerabie.com/sdks/mcp

MIT licensed.
