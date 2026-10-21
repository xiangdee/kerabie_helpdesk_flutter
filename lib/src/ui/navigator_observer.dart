import 'package:flutter/widgets.dart';

import '../provider.dart';

/// The route name the chat screen is pushed under. Screens with this name are not reported as the customer's screen.
const kerabieChatRouteName = '/kerabie-chat';

/// Tells Kerabie which screen the customer is on, from your routes' names. Add it to your `MaterialApp`:
///
/// ```dart
/// MaterialApp(navigatorKey: navigatorKey, navigatorObservers: [KerabieNavigatorObserver()])
/// ```
///
/// Agents see the page the customer is on, and campaigns can be limited to certain screens. Only named page routes
/// count: dialogs, sheets and unnamed routes are ignored. With `go_router` or another router that has no route names,
/// call `KerabieProvider.of(context).trackScreen('/path')` yourself.
class KerabieNavigatorObserver extends NavigatorObserver {
  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    final context = navigator?.context;
    if (route is! PageRoute || name == null || name == kerabieChatRouteName || context == null) return;
    final controller = KerabieProvider.maybeOf(context, listen: false);
    // Routes change while the navigator is building; tell the chat afterwards, not in the middle of that.
    if (controller != null) Future.microtask(() => controller.trackScreen(name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _track(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(previousRoute);
}
