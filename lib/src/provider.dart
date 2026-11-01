import 'dart:async';
import 'dart:convert';
import 'agent.dart';
import 'ui/agent_screens.dart';
import 'package:flutter/widgets.dart';

import 'campaigns.dart';
import 'config.dart';
import 'controller.dart';
import 'models.dart';
import 'person.dart';
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
    this.agent,
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

  /// The AI agent in the chat: who is signed in ([KerabieAgentOptions.getUserToken]) and what your app can do for it.
  /// A list, a confirmation and an address box are built in; add `pick_saved_address`, `pick_schedule` and `open_screen`
  /// as [KerabieAgentOptions.screens], and things your app does itself (add to its own cart) as
  /// [KerabieAgentOptions.actions]. Screens need the [navigatorKey] (the same one as your MaterialApp). Without this the
  /// chat is unchanged.
  final KerabieAgentOptions? agent;

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
    _syncUser(old.config.user, widget.config.user);
  }

  /// The user in [KerabieConfig] is followed after the first build: signing in gives the person's name to the team, and
  /// signing out forgets it. A session belongs to one person: when someone else signs in after a signed-in person (or
  /// nobody does), the session, the conversations and the connection are started again, so nothing carries over.
  void _syncUser(KerabieUser? before, KerabieUser? after) {
    if (jsonEncode(before?.toJson()) == jsonEncode(after?.toJson())) return;
    final before0 = kerabiePersonOf(before);
    final switched = before0.isNotEmpty && before0 != kerabiePersonOf(after);
    unawaited(() async {
      if (switched) await _controller.clearUser();
      if (after != null) {
        await _controller.setUser(after);
      } else if (!switched) {
        await _controller.clearUser();
      }
    }());
  }

  void _syncCallbacks() {
    _controller
      ..onNavigate = widget.onNavigate
      ..onOpenChat = widget.onOpenChat
      ..onCloseChat = widget.onCloseChat
      ..onOpenKnowledgeBase = widget.onOpenKnowledgeBase
      ..callActions = widget.callActions;
    final agent = widget.agent;
    _controller.agent = agent == null
        ? null
        : KerabieAgentOptions(
            getUserToken: agent.getUserToken,
            // Dialogs are shown from the navigator's overlay, so they appear over whatever screen the customer is on.
            screens: {...builtInAgentScreens(_dialogContext), ...agent.screens},
            actions: agent.actions,
          );
  }

  BuildContext _dialogContext() => widget.navigatorKey?.currentState?.overlay?.context ?? context;

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
