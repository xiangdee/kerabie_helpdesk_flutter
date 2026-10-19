import 'package:flutter/material.dart';

import '../models.dart';
import 'palette.dart';

/// One message. The visitor's are on the right in the brand colour, agents' and the AI's on the left.
class KerabieMessageBubble extends StatelessWidget {
  const KerabieMessageBubble({super.key, required this.message, required this.palette, this.onRetry, this.botAvatarUrl});

  final KerabieMessage message;
  final KerabiePalette palette;

  /// The picture beside the AI assistant's replies. A sparkle icon when null.
  final String? botAvatarUrl;

  /// Called when the visitor taps a message that failed to send.
  final VoidCallback? onRetry;

  Widget _botMark() {
    final icon = Icon(Icons.auto_awesome, size: 16, color: palette.muted);
    final url = botAvatarUrl;
    if (url == null) return icon;
    return ClipOval(
      child: Image.network(url, width: 20, height: 20, fit: BoxFit.cover, errorBuilder: (_, __, ___) => icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.isFromVisitor;
    final failed = message.status == KerabieMessageStatus.failed;
    final radius = Radius.circular(palette.radius);
    final tail = Radius.circular(palette.radius > 6 ? 4 : palette.radius);
    final bubble = DecoratedBox(
      decoration: () {
        final corners = BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: mine ? radius : tail,
          bottomRight: mine ? tail : radius,
        );
        return mine
            ? palette.userBubbleDecoration(corners)
            : BoxDecoration(color: palette.agentBubble, borderRadius: corners);
      }(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: message.body),
            if (message.streaming) const TextSpan(text: ' ▍'),
          ]),
          style: TextStyle(color: mine ? palette.onUserBubble : palette.text, fontSize: 15, height: 1.35),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine && message.sender == KerabieSender.bot) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: _botMark(),
            ),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  GestureDetector(onTap: failed ? onRetry : null, child: bubble),
                  if (mine && message.status != KerabieMessageStatus.sent)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        failed ? 'Not sent. Tap to retry' : 'Sending',
                        style: TextStyle(fontSize: 11, color: failed ? Colors.red.shade400 : palette.muted),
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

/// Shown at the bottom of the list while an agent or the AI is typing.
class KerabieTypingBubble extends StatelessWidget {
  const KerabieTypingBubble({super.key, required this.palette, required this.ai});

  final KerabiePalette palette;
  final bool ai;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(color: palette.agentBubble, borderRadius: BorderRadius.circular(palette.radius)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(ai ? 'Thinking…' : 'Typing…', style: TextStyle(color: palette.muted, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}
