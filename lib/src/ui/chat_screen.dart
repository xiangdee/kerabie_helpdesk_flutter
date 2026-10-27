import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../controller.dart';
import '../guided.dart';
import '../models.dart';
import '../provider.dart';
import 'article_card.dart';
import 'dialog.dart';
import 'guided_choices.dart';
import 'image_viewer.dart';
import 'indicators.dart';
import 'input_bar.dart';
import 'knowledge_base_screen.dart';
import 'links.dart';
import 'message_bubble.dart';
import 'navigator_observer.dart';
import 'palette.dart';
import 'pre_chat_form.dart';
import 'settings_screen.dart';
import 'widget_shell.dart';

const _defaultPreChatFields = [
  KerabieEnrichmentField(key: 'name', label: 'Your name', placeholder: 'Your name'),
  KerabieEnrichmentField(key: 'email', label: 'Email address', type: 'email', placeholder: 'Email address'),
];

/// `{{name}}` becomes the visitor's first name. With no known name the token and the space before it are dropped
/// ("Hi {{name}} 👋" becomes "Hi 👋").
String kerabiePersonalize(String text, String? visitorName) {
  final first = (visitorName ?? '').trim().split(RegExp(r'\s+')).first;
  return text.replaceAllMapped(RegExp(r'\s*\{\{\s*name\s*\}\}', caseSensitive: false), (m) {
    if (first.isEmpty) return '';
    return m.group(0)!.replaceFirst(RegExp(r'\{\{\s*name\s*\}\}', caseSensitive: false), first);
  });
}

/// Opens the chat screen.
class KerabieChat {
  const KerabieChat._();

  /// Shows the chat over the app, the way [KerabieConfig.openMode] says. Call it from a button, or use [KerabieLauncher].
  static Future<void> show(BuildContext context) {
    final controller = KerabieProvider.of(context, listen: false);
    return showOn(Navigator.of(context, rootNavigator: true), controller);
  }

  /// Shows the chat on a navigator you already hold, for example from a link or a notification tap.
  static Future<void> showOn(
    NavigatorState navigator,
    KerabieController controller, {
    KerabieRoute route = const KerabieRoute(KerabieRouteType.inbox),
  }) {
    final mode = controller.config.openMode;
    // In push mode the app opens its own screen, which shows a KerabieChatScreen.
    final onNavigate = controller.onNavigate;
    if (mode == KerabieOpenMode.push && onNavigate != null) {
      onNavigate(route);
      return Future.value();
    }
    if (_showing[controller] == true) return Future.value();
    _showing[controller] = true;
    controller.dismisser = navigator.maybePop;
    final Future<void> shown;
    if (mode == KerabieOpenMode.sheet) {
      shown = showModalBottomSheet<void>(
        context: navigator.context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => KerabieScope(
          notifier: controller,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(height: MediaQuery.sizeOf(navigator.context).height * 0.92, child: KerabieWidget(initialRoute: route)),
          ),
        ),
      );
    } else {
      shown = navigator.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: kerabieChatRouteName),
        fullscreenDialog: true,
        builder: (_) => KerabieScope(notifier: controller, child: KerabieWidget(initialRoute: route)),
      ));
    }
    return shown.whenComplete(() {
      _showing[controller] = false;
      controller.dismisser = null;
    });
  }

  // Whether the chat screen is on the navigator for a given controller.
  static final Expando<bool> _showing = Expando<bool>();
}

/// Just the conversation: header, messages and the box to write in, without the tabs. Use [KerabieWidget] for the
/// whole widget; use this when you want your own navigation around the chat. [KerabieOpenMode.push] apps can put
/// either in their own route and pass [onClose] to leave it.
class KerabieChatScreen extends StatefulWidget {
  const KerabieChatScreen({super.key, this.onClose, this.onBack, this.embedded = false});

  /// Called by the close button. Defaults to leaving the current route.
  final VoidCallback? onClose;

  /// Shows a back arrow instead of the connection dot, and drops the settings button (settings live in the Help tab).
  final VoidCallback? onBack;

  /// Set by [KerabieWidget], which marks the chat open and closed itself as the visitor moves between tabs.
  final bool embedded;

  @override
  State<KerabieChatScreen> createState() => _KerabieChatScreenState();
}

class _KerabieChatScreenState extends State<KerabieChatScreen> {
  final _input = TextEditingController();
  Timer? _typingStop;
  Timer? _offlineTimer;
  KerabieController? _controller;
  bool _showSettings = false;
  bool _showOffline = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = KerabieProvider.of(context, listen: false);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onController);
      _controller = controller..addListener(_onController);
      if (!widget.embedded) WidgetsBinding.instance.addPostFrameCallback((_) => controller.open());
      _onController();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onController);
    // After this frame: closing tells listeners, which must not happen while the tree is being torn down.
    if (controller != null && !widget.embedded) Future.microtask(controller.close);
    _typingStop?.cancel();
    _offlineTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  bool _draftBeingHandled = false;
  int? _markedId;
  int _markedCount = -1;

  void _onController() {
    final controller = _controller!;
    // A drop that lasts three seconds shows the banner, so a normal reconnect does not flash it.
    if (controller.isConnected) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      if (_showOffline) setState(() => _showOffline = false);
    } else {
      _offlineTimer ??= Timer(const Duration(seconds: 3), () {
        if (mounted && !controller.isConnected) setState(() => _showOffline = true);
      });
    }
    // While this chat is on screen everything in it counts as read, including replies that arrive meanwhile.
    final id = controller.conversationId;
    final count = controller.messages.length;
    if (id != null && (id != _markedId || count != _markedCount)) {
      _markedId = id;
      _markedCount = count;
      controller.markConversationRead(id);
    }
    // Handed over by the search bar: the visitor already pressed send there, so the text goes out now, unless the
    // pre-chat form still has to collect their details, in which case it waits in the composer.
    final draft = controller.chatDraft;
    if (draft != null && !_draftBeingHandled) {
      _draftBeingHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _draftBeingHandled = false;
        if (!mounted) return;
        controller.clearChatDraft();
        if (_showPreChat(controller)) {
          _input.text = draft;
        } else if (draft.trim().isNotEmpty || controller.staging.pending != null) {
          controller.sendMessage(draft);
        }
      });
    }
  }

  bool _isOfflineNoBot(KerabieController c) => (c.agentsOnline ?? 0) == 0 && c.chat.chatbotEnabled != true;

  List<KerabieEnrichmentField> _preChatFields(KerabieController c) {
    final custom = c.chat.customerEnrichmentEnabled == true ? c.chat.customerEnrichmentForm ?? const [] : const <KerabieEnrichmentField>[];
    return custom.isNotEmpty ? custom : _defaultPreChatFields;
  }

  bool _showPreChat(KerabieController c) {
    final user = c.currentUser;
    final answered = (user?.name?.isNotEmpty ?? false) || (user?.email?.isNotEmpty ?? false) || (user?.customAttributes.isNotEmpty ?? false);
    return (c.chat.customerEnrichmentEnabled == true || _isOfflineNoBot(c)) && !answered && c.messages.isEmpty;
  }

  void _submitPreChat(KerabieController c, Map<String, String> answers) {
    // name, email and phone are the contact's own fields; every other answer is a custom attribute.
    var user = c.currentUser ?? const KerabieUser();
    final custom = {...user.customAttributes};
    for (final f in _preChatFields(c)) {
      final v = (answers[f.key] ?? '').trim();
      if (v.isEmpty) continue;
      switch (f.key) {
        case 'name':
          user = user.copyWith(name: v);
        case 'email':
          user = user.copyWith(email: v);
        case 'phone':
          user = user.copyWith(phone: v);
        default:
          custom[f.key] = v;
      }
    }
    c.setUser(user.copyWith(customAttributes: custom));
  }

  void _onChanged(String text, KerabieController controller) {
    if (text.isEmpty) return;
    if (_typingStop == null) controller.sendTyping(true);
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(milliseconds: 1500), () {
      _typingStop = null;
      controller.sendTyping(false);
    });
  }

  void _send(KerabieController controller) {
    final text = _input.text.trim();
    if (text.isEmpty && controller.staging.pending == null) return;
    _input.clear();
    if (_typingStop != null) {
      _typingStop!.cancel();
      _typingStop = null;
      controller.sendTyping(false);
    }
    controller.sendMessage(text);
  }

  Future<void> _chooseAttachment(KerabieController controller, KerabiePalette palette) {
    return showKerabieDialog<void>(
      context: context,
      palette: palette,
      title: 'Send attachment',
      body: (ctx) => Column(
        children: [
          for (final option in const [('Photo', true), ('Document', false)])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(side: BorderSide(color: palette.border, width: 0.5), padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    option.$2 ? controller.pickPhoto() : controller.pickDocument();
                  },
                  child: Text(option.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text)),
                ),
              ),
            ),
        ],
      ),
      actions: (_) => const [],
    );
  }

  Widget _header(KerabieController controller, KerabiePalette palette) {
    final chat = controller.chat;
    final agents = controller.agentsOnline ?? 0;
    final menu = widget.onBack == null && (chat.layout != KerabieLayout.single || chat.showMenu == true);
    return DecoratedBox(
      decoration: palette.brandDecoration,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 12),
          child: Row(
            children: [
              if (_showSettings || widget.onBack != null)
                IconButton(
                  tooltip: 'Back',
                  onPressed: _showSettings ? () => setState(() => _showSettings = false) : widget.onBack,
                  icon: Icon(Icons.chevron_left_rounded, color: palette.onPrimary),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 10),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: controller.isConnected ? const Color(0xFF45EE95) : palette.onPrimary.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showSettings ? 'Settings' : (chat.name ?? 'Support'),
                      style: TextStyle(color: palette.onPrimary, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: palette.fontFamily),
                    ),
                    if (!_showSettings)
                      Text(
                        agents > 0 ? '$agents agent${agents > 1 ? 's' : ''} online' : (chat.offlineMessage ?? "We'll reply soon"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.onPrimary.withValues(alpha: 0.85), fontSize: 12, fontFamily: palette.fontFamily),
                      ),
                  ],
                ),
              ),
              if (!_showSettings && menu)
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => setState(() => _showSettings = true),
                  icon: Icon(Icons.settings_outlined, size: 20, color: palette.onPrimary),
                ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close_rounded, color: palette.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages(KerabieController controller, KerabiePalette palette) {
    final messages = controller.messages;
    final chat = controller.chat;
    final greeting = controller.guidedGreeting;
    if (messages.isEmpty && greeting != null) {
      // The organisation's guided flow opens the chat with a question and buttons. It is only on screen here; the
      // server saves it as the conversation's first message once a button is tapped.
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: KerabieMessageBubble(
            message: KerabieMessage(id: 'guided-greeting', body: greeting.message, createdAt: DateTime.now(), sender: KerabieSender.bot),
            palette: palette,
            botAvatarUrl: controller.config.theme.chatbotAvatarUrl ?? controller.settings.chatbotAvatarUrl,
          ),
        ),
      );
    }
    if (messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                child: Icon(Icons.chat_bubble_outline_rounded, size: 24, color: palette.accent),
              ),
              const SizedBox(height: 12),
              Text(
                kerabiePersonalize(chat.welcomeMessage ?? 'Hi there! How can we help you today?', controller.visitorName),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.text, fontFamily: palette.fontFamily),
              ),
            ],
          ),
        ),
      );
    }
    // The list is reversed so new messages sit at the bottom and the keyboard pushes it up naturally.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: messages.length,
      itemBuilder: (_, index) {
        final message = messages[messages.length - 1 - index];
        return KerabieMessageBubble(
          key: ValueKey(message.id),
          message: message,
          palette: palette,
          botAvatarUrl: controller.config.theme.chatbotAvatarUrl ?? controller.settings.chatbotAvatarUrl,
          onRetry: () => controller.retry(message),
          onOpenImage: (url) => showKerabieImageViewer(context, url),
          onOpenArticle: (cite) => showKerabieArticleSheet(context, controller, palette, cite.id, cite.title),
          citationBuilder: (cite) => KerabieArticleCard(
            controller: controller,
            citation: cite,
            palette: palette,
            onOpen: (article) => showKerabieArticleSheet(context, controller, palette, cite.id, article?.title ?? cite.title,
                content: article?.content, imageUrl: article?.imageUrl),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final chat = controller.chat;
    final staging = controller.staging;
    final preChat = _showPreChat(controller);
    final offlineNoBot = _isOfflineNoBot(controller);
    final fields = _preChatFields(controller);
    // Guided flow buttons: the greeting's, or those on the latest bot message until the visitor answers it.
    final guided = kerabieActiveChoices(controller.messages, controller.guidedGreeting, greetingAllowed: !preChat);

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(controller, palette),
          if (_showSettings)
            Expanded(child: KerabieSettingsScreen(controller: controller, palette: palette))
          else ...[
            if (_showOffline)
              Container(
                width: double.infinity,
                color: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: const Text(
                  "Can't reach chat right now — reconnecting…",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            Expanded(child: _messages(controller, palette)),
            if (preChat)
              KerabiePreChatForm(
                fields: fields,
                title: offlineNoBot ? "We're offline right now" : 'Before we start',
                subtitle: offlineNoBot ? "Leave your details and we'll get back to you" : 'Share your details so we can follow up',
                submitLabel: offlineNoBot ? 'Send' : 'Start chat',
                requireContact: identical(fields, _defaultPreChatFields),
                initial: {'name': controller.currentUser?.name ?? '', 'email': controller.currentUser?.email ?? ''},
                palette: palette,
                onSubmit: (answers) => _submitPreChat(controller, answers),
              ),
            if (controller.isTyping && chat.typingIndicator != false)
              controller.isAiTyping ? KerabieAiOrb(palette: palette) : KerabieTypingDots(palette: palette),
            if (guided != null)
              KerabieGuidedChoices(
                choices: guided.choices,
                palette: palette,
                disabled: !controller.isConnected,
                onPick: (c) => controller.sendMessage(c.label, choice: (flowId: guided.flowId, choiceId: c.id)),
              ),
            ListenableBuilder(
              listenable: staging,
              builder: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (staging.error != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA), width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(staging.error!, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFB91C1C)))),
                          InkWell(onTap: staging.dismissError, child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFB91C1C))),
                        ],
                      ),
                    ),
                  KerabieInputBar(
                    controller: _input,
                    palette: palette,
                    storage: controller.storage,
                    disabled: !controller.isConnected,
                    placeholder: controller.isConnected ? null : 'Waiting for connection…',
                    pending: staging.pending,
                    isUploading: staging.isUploading,
                    onRemoveAttachment: staging.remove,
                    onAttach: chat.enableFileAttachments == false ? null : () => _chooseAttachment(controller, palette),
                    onChanged: (t) => _onChanged(t, controller),
                    onSend: () => _send(controller),
                  ),
                ],
              ),
            ),
            if (chat.showBranding != false)
              SafeArea(
                top: false,
                child: InkWell(
                  onTap: () => openKerabieLink('https://kerabie.com/?utm_source=widget&utm_medium=powered_by'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text.rich(
                      TextSpan(
                        text: 'Powered by ',
                        children: [TextSpan(text: 'Kerabie', style: TextStyle(fontWeight: FontWeight.w600, color: palette.muted))],
                      ),
                      style: TextStyle(fontSize: 11, color: palette.subtle),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
