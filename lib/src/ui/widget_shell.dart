import 'package:flutter/material.dart';

import '../config.dart';
import '../controller.dart';
import '../provider.dart';
import 'chat_screen.dart';
import 'conversations_screen.dart';
import 'help_screen.dart';
import 'home_screen.dart';
import 'palette.dart';
import 'tickets_screen.dart';
import 'widget_tab_bar.dart';

/// The whole widget: Home, Chat, Help and (when the organisation has them on) Tickets behind a bottom tab bar, the same
/// structure as the web widget. The full layout's Chat tab is the list of conversations (with New chat); the single
/// layout is one continuous chat, so it opens straight on it and only shows the tabs when the dashboard's "Show
/// navigation" is on.
///
/// [KerabieChat.show] puts this on screen. With [KerabieOpenMode.push], show it in your own route and pass [onClose].
class KerabieWidget extends StatefulWidget {
  const KerabieWidget({super.key, this.onClose, this.initialRoute = const KerabieRoute(KerabieRouteType.inbox)});

  /// Called by the close buttons. Defaults to leaving the current route.
  final VoidCallback? onClose;

  /// A conversation route (from a notification tap or link) opens on that chat instead of Home.
  final KerabieRoute initialRoute;

  @override
  State<KerabieWidget> createState() => _KerabieWidgetState();
}

class _KerabieWidgetState extends State<KerabieWidget> {
  KerabieController? _controller;
  late KerabieTab _tab;
  // Inside the Chat tab of the full layout: the list of chats, or one open chat.
  late bool _chatOpen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = KerabieProvider.of(context, listen: false);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onController);
    _controller = controller..addListener(_onController);
    final single = controller.chat.layout == KerabieLayout.single;
    final toChat = single || controller.chatDraft != null || widget.initialRoute.type == KerabieRouteType.conversation;
    _tab = toChat ? KerabieTab.chat : KerabieTab.home;
    _chatOpen = toChat;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.open());
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onController);
    // After this frame: closing tells listeners, which must not happen while the tree is being torn down.
    if (controller != null) Future.microtask(controller.close);
    super.dispose();
  }

  // A search-bar draft goes straight to a chat.
  void _onController() {
    final controller = _controller!;
    if (controller.chatDraft != null && (_tab != KerabieTab.chat || !_chatOpen) && mounted) {
      setState(() {
        _tab = KerabieTab.chat;
        _chatOpen = true;
      });
    }
  }

  void _close() => widget.onClose != null ? widget.onClose!() : Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final chat = controller.chat;
    final single = chat.layout == KerabieLayout.single;
    final showTabs = !single || chat.showNavigation == true;
    final tickets = controller.settings.ticketsEnabled;
    final tab = _tab == KerabieTab.tickets && !tickets ? KerabieTab.home : _tab;
    final inChat = tab == KerabieTab.chat && _chatOpen;

    final Widget body = switch (tab) {
      KerabieTab.home => KerabieHomeScreen(
          controller: controller,
          palette: palette,
          onClose: _close,
          // "Ask our AI" / "Chat with us" is a fresh chat (the single layout has just the one).
          onChat: () {
            if (!single) controller.startNewConversation();
            setState(() {
              _tab = KerabieTab.chat;
              _chatOpen = true;
            });
          },
        ),
      KerabieTab.chat when !_chatOpen => KerabieConversationsScreen(
          controller: controller,
          palette: palette,
          onNew: () {
            controller.startNewConversation();
            setState(() => _chatOpen = true);
          },
          onOpen: (id) {
            controller.openConversation(id);
            setState(() => _chatOpen = true);
          },
        ),
      KerabieTab.chat => KerabieChatScreen(
          embedded: true,
          onClose: _close,
          onBack: showTabs ? () => setState(() => single ? _tab = KerabieTab.home : _chatOpen = false) : null,
        ),
      KerabieTab.help => KerabieHelpScreen(controller: controller, palette: palette),
      KerabieTab.tickets => KerabieTicketsScreen(onClose: () => setState(() => _tab = KerabieTab.home)),
    };

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          Expanded(child: body),
          if (showTabs && !inChat)
            KerabieTabBar(
              active: tab,
              ticketsEnabled: tickets,
              unread: controller.unreadCount,
              palette: palette,
              onChanged: (next) => setState(() {
                _tab = next;
                if (next == KerabieTab.chat) _chatOpen = single; // the full layout lands on the list
              }),
            ),
        ],
      ),
    );
  }
}
