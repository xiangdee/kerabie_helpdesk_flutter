import 'package:flutter/widgets.dart';

import 'campaigns.dart';
import 'config.dart';
import 'controller.dart';
import 'ui/campaign_banner.dart';
import 'ui/chat_screen.dart';
import 'ui/links.dart';
import 'ui/palette.dart';

/// Gives the widgets below it access to the Kerabie chat. Put it above your `MaterialApp`.
///
/// Pass the same [navigatorKey] to your `MaterialApp` and the chat can also open from a link or a tapped
/// notification, not only from the launcher, and campaigns can pop up over your screens.
class KerabieProvider extends StatefulWidget {
  const KerabieProvider({
    super.key,
    required this.config,
    required this.child,
    this.navigatorKey,
    this.controller,
    this.onNavigate,
    this.onOpenChat,
    this.onCloseChat,
    this.onOpenKnowledgeBase,
    this.callActions,
  });

  final KerabieConfig config;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Supply your own controller (for example in tests). When null the provider creates and disposes one.
  final KerabieController? controller;

  /// With [KerabieOpenMode.push]: called when the chat should open in your own navigator. Show a [KerabieChatScreen]
  /// there. Without it the chat opens as a full-screen page.
  final void Function(KerabieRoute route)? onNavigate;

  /// Called when the chat opens and closes.
  final VoidCallback? onOpenChat;
  final VoidCallback? onCloseChat;

  /// A campaign button can open your knowledge base. Chat has no fixed screen for it, so the app decides where it
  /// goes, for example to a [KerabieKnowledgeBaseScreen]. Without this the chat opens instead.
  final VoidCallback? onOpenKnowledgeBase;

  /// Shown in the chat header, next to Settings. Pass `KerabieCallButton.icon()` from `kerabie_helpdesk_flutter_calls`
  /// to put call buttons in the chat. It is a widget you pass in, so this package never carries the call code.
  final Widget? callActions;

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
  KerabieCampaigns? _campaigns;
  OverlayEntry? _bannerEntry;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? KerabieController(config: widget.config);
    _controller.presenter = _present;
    _syncCallbacks();
    if (_ownsController) _controller.start();
    _campaigns = KerabieCampaigns(_controller);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame(0));
  }

  @override
  void didUpdateWidget(KerabieProvider old) {
    super.didUpdateWidget(old);
    _syncCallbacks();
  }

  void _syncCallbacks() {
    _controller
      ..onNavigate = widget.onNavigate
      ..onOpenChat = widget.onOpenChat
      ..onCloseChat = widget.onCloseChat
      ..onOpenKnowledgeBase = widget.onOpenKnowledgeBase
      ..callActions = widget.callActions;
  }

  /// The navigator does not exist until the app below has built, so wait for it: the banner needs its overlay, and
  /// `defaultOpen` needs it to open the chat.
  void _afterFirstFrame(int attempt) {
    if (!mounted) return;
    final navigator = widget.navigatorKey?.currentState;
    if (navigator == null) {
      if (attempt < 10 && widget.navigatorKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame(attempt + 1));
      }
      return;
    }
    _insertBanner(navigator);
    if (widget.config.defaultOpen) _controller.showChat();
  }

  void _insertBanner(NavigatorState navigator) {
    final overlay = navigator.overlay;
    final campaigns = _campaigns;
    if (overlay == null || campaigns == null || _bannerEntry != null) return;
    _bannerEntry = OverlayEntry(
      builder: (context) => ListenableBuilder(
        listenable: campaigns,
        builder: (context, _) {
          final campaign = campaigns.current;
          if (campaign == null) return const SizedBox.shrink();
          final palette = KerabiePalette.of(context, _controller);
          return KerabieCampaignBanner(
            campaign: campaign,
            palette: palette,
            name: _controller.chat.name ?? _controller.appName,
            position: _controller.config.position,
            onDismiss: campaigns.dismiss,
            onOpen: () {
              campaigns.engage(withClick: false);
              _controller.showChat();
            },
            onCta: () {
              campaigns.engage(withClick: true);
              if (campaign.ctaAction == 'open_link') {
                // The API only accepts http(s) links; check again so a bad value can never launch another scheme.
                final url = campaign.ctaUrl;
                if (url != null && RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) openKerabieLink(url);
              } else if (campaign.ctaAction == 'open_kb' && _controller.onOpenKnowledgeBase != null) {
                _controller.onOpenKnowledgeBase!();
              } else {
                _controller.showChat();
              }
            },
          );
        },
      ),
    );
    overlay.insert(_bannerEntry!);
  }

  void _present(KerabieRoute route) {
    final navigator = widget.navigatorKey?.currentState;
    if (navigator != null) {
      KerabieChat.showOn(navigator, _controller, route: route);
    } else {
      _controller.open();
    }
  }

  @override
  void dispose() {
    _bannerEntry?.remove();
    _bannerEntry?.dispose();
    _campaigns?.dispose();
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
