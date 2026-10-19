import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../provider.dart';
import 'message_bubble.dart';
import 'palette.dart';

/// Opens the chat screen.
class KerabieChat {
  const KerabieChat._();

  /// Shows the chat over the app. Call it from a button, or use [KerabieLauncher].
  static Future<void> show(BuildContext context) {
    final controller = KerabieProvider.of(context, listen: false);
    return showOn(Navigator.of(context, rootNavigator: true), controller);
  }

  /// Shows the chat on a navigator you already hold, for example from a link or a notification tap.
  static Future<void> showOn(NavigatorState navigator, KerabieController controller) {
    if (_showing[controller] == true) return Future.value();
    _showing[controller] = true;
    controller.open();
    return navigator
        .push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => KerabieScope(notifier: controller, child: const KerabieChatScreen()),
        ))
        .whenComplete(() {
      _showing[controller] = false;
      controller.close();
    });
  }

  // Whether the chat screen is on the navigator for a given controller.
  static final Expando<bool> _showing = Expando<bool>();
}

/// The conversation: header, messages and the box to write in.
class KerabieChatScreen extends StatefulWidget {
  const KerabieChatScreen({super.key});

  @override
  State<KerabieChatScreen> createState() => _KerabieChatScreenState();
}

class _KerabieChatScreenState extends State<KerabieChatScreen> {
  final _input = TextEditingController();
  Timer? _typingStop;
  bool _typingSent = false;

  @override
  void dispose() {
    _typingStop?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String text, KerabieController controller) {
    if (text.isEmpty) return;
    if (!_typingSent) {
      _typingSent = true;
      controller.sendTyping(true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), () {
      _typingSent = false;
      controller.sendTyping(false);
    });
  }

  void _send(KerabieController controller) {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _typingStop?.cancel();
    if (_typingSent) {
      _typingSent = false;
      controller.sendTyping(false);
    }
    controller.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final settings = controller.settings;
    final messages = controller.messages;
    final welcome = settings.welcomeMessage;
    final online = (controller.agentsOnline ?? 0) > 0;

    // The list is reversed so new messages sit at the bottom and the keyboard pushes it up naturally.
    final itemCount = messages.length + (controller.isTyping ? 1 : 0) + (welcome != null && welcome.isNotEmpty ? 1 : 0);

    Widget item(int index) {
      var i = index;
      if (controller.isTyping) {
        if (i == 0) return KerabieTypingBubble(palette: palette, ai: controller.isAiTyping);
        i -= 1;
      }
      if (i < messages.length) {
        final message = messages[messages.length - 1 - i];
        return KerabieMessageBubble(
          message: message,
          palette: palette,
          botAvatarUrl: settings.chatbotAvatarUrl,
          onRetry: () => controller.retry(message),
        );
      }
      return KerabieMessageBubble(
        message: KerabieMessage(
          id: 'welcome',
          body: welcome!,
          createdAt: DateTime.now(),
          sender: KerabieSender.agent,
        ),
        palette: palette,
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          DecoratedBox(
            decoration: palette.brandDecoration,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.name ?? 'Support',
                            style: TextStyle(color: palette.onPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: online ? const Color(0xFF45EE95) : palette.onPrimary.withValues(alpha: 0.45),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  online ? 'Online' : (settings.offlineMessage ?? 'We will reply as soon as we can'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: palette.onPrimary.withValues(alpha: 0.85), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.close_rounded, color: palette.onPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: itemCount,
              itemBuilder: (_, index) => item(index),
            ),
          ),
          if (settings.showBranding)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Powered by Kerabie', style: TextStyle(fontSize: 11, color: palette.muted)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (t) => _onChanged(t, controller),
                      style: TextStyle(color: palette.text),
                      decoration: InputDecoration(
                        hintText: 'Write a message',
                        hintStyle: TextStyle(color: palette.muted),
                        filled: true,
                        fillColor: palette.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: palette.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _send(controller),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.send_rounded, size: 20, color: palette.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
