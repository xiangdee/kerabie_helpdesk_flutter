import 'package:flutter/widgets.dart';

import 'config.dart';
import 'controller.dart';
import 'ui/chat_screen.dart';

/// Gives the widgets below it access to the Kerabie chat. Put it above your `MaterialApp`.
///
/// Pass the same [navigatorKey] to your `MaterialApp` and the chat can also open from a link or a tapped
/// notification, not only from the launcher.
class KerabieProvider extends StatefulWidget {
  const KerabieProvider({
    super.key,
    required this.config,
    required this.child,
    this.navigatorKey,
    this.controller,
  });

  final KerabieConfig config;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Supply your own controller (for example in tests). When null the provider creates and disposes one.
  final KerabieController? controller;

  /// The controller, rebuilding the caller when the chat changes. Pass `listen: false` from callbacks.
  static KerabieController of(BuildContext context, {bool listen = true}) {
    final controller = maybeOf(context, listen: listen);
    assert(controller != null, 'KerabieProvider not found. Put it above your MaterialApp.');
    return controller!;
  }

  static KerabieController? maybeOf(BuildContext context, {bool listen = true}) {
    if (listen) return context.dependOnInheritedWidgetOfExactType<KerabieScope>()?.notifier;
    return context.getInheritedWidgetOfExactType<KerabieScope>()?.notifier;
  }

  @override
  State<KerabieProvider> createState() => _KerabieProviderState();
}

class _KerabieProviderState extends State<KerabieProvider> {
  late final KerabieController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KerabieController(config: widget.config);
    _controller.presenter = _present;
    if (_ownsController) _controller.start();
  }

  void _present() {
    final navigator = widget.navigatorKey?.currentState;
    if (navigator != null) {
      KerabieChat.showOn(navigator, _controller);
    } else {
      _controller.open();
    }
  }

  @override
  void dispose() {
    _controller.presenter = null;
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KerabieScope(notifier: _controller, child: widget.child);
}

/// The inherited widget behind [KerabieProvider]. Rebuilds dependants whenever the controller notifies.
class KerabieScope extends InheritedNotifier<KerabieController> {
  const KerabieScope({super.key, required KerabieController super.notifier, required super.child});
}
