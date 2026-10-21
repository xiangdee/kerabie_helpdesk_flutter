import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'indicators.dart';
import 'links.dart';
import 'palette.dart';

String _initials(String? name) {
  final parts = (name ?? 'A').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// One message. The visitor's are on the right in the brand colour, agents' and the AI's on the left.
class KerabieMessageBubble extends StatelessWidget {
  const KerabieMessageBubble({
    super.key,
    required this.message,
    required this.palette,
    this.onRetry,
    this.botAvatarUrl,
    this.onOpenImage,
    this.onOpenArticle,
  });

  final KerabieMessage message;
  final KerabiePalette palette;

  /// The picture beside the AI assistant's replies. A robot on a purple disc when null.
  final String? botAvatarUrl;

  /// Called when the visitor taps a message that failed to send.
  final VoidCallback? onRetry;

  /// Called with the image to show full screen.
  final ValueChanged<String>? onOpenImage;

  /// Called when a knowledge base article under an AI reply is tapped.
  final ValueChanged<KerabieCitation>? onOpenArticle;

  Widget _avatar() {
    Widget disc(Color color, Widget child) => Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 6, bottom: 4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          alignment: Alignment.center,
          child: child,
        );
    Widget photo(String url, Widget fallback) => Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 6, bottom: 4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
          clipBehavior: Clip.antiAlias,
          child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
        );
    final robot = disc(const Color(0xFF6366F1), const Text('🤖', style: TextStyle(fontSize: 12)));
    if (message.sender == KerabieSender.bot) {
      return botAvatarUrl == null ? robot : photo(botAvatarUrl!, robot);
    }
    final initials = disc(palette.primary, Text(_initials(message.senderName), style: TextStyle(fontSize: 12, color: palette.onPrimary)));
    final avatar = message.senderAvatar;
    return avatar == null ? initials : photo(avatar, initials);
  }

  Widget _attachment(Color textColor, bool mine) {
    final url = message.attachmentUrl;
    if (url == null || (message.type != 'image' && message.type != 'file')) return const SizedBox.shrink();
    final child = message.type == 'image'
        ? GestureDetector(
            onTap: () => onOpenImage?.call(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _image(url),
            ),
          )
        : GestureDetector(
            onTap: () => openKerabieLink(url),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('📎 ${message.attachmentName ?? 'File'}', style: TextStyle(fontSize: 13, color: mine ? textColor : palette.text)),
            ),
          );
    return Padding(padding: EdgeInsets.only(bottom: message.body.isNotEmpty ? 6 : 0), child: child);
  }

  Widget _image(String url) {
    const size = Size(200, 150);
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(url, width: size.width, height: size.height, fit: BoxFit.cover, cacheWidth: 400);
    }
    return Image(
      image: ResizeImage(FileImage(File(url)), width: 400),
      width: size.width,
      height: size.height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(width: size.width, height: size.height, child: const Icon(Icons.broken_image_outlined)),
    );
  }

  Widget _linkPreview() {
    final preview = message.linkPreview;
    if (preview == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => openKerabieLink(preview.url),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.image != null)
                Image.network(preview.image!, width: double.infinity, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preview.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3, color: palette.text)),
                    if (preview.description != null && preview.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(preview.description!,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.3, color: palette.muted)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          if (preview.favicon != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Image.network(preview.favicon!, width: 11, height: 11, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                            ),
                          Flexible(
                            child: Text(
                              (preview.siteName?.isNotEmpty ?? false) ? preview.siteName! : hostnameOf(preview.url),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: palette.subtle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _citation(KerabieCitation cite, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => onOpenArticle?.call(cite),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border, width: 0.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('📄 ${cite.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: textColor)),
              ),
              const SizedBox(width: 6),
              Text('›', style: TextStyle(fontSize: 13, color: palette.muted)),
            ],
          ),
        ),
      ),
    );
  }

  String _time(BuildContext context) {
    final local = message.createdAt.toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.isFromVisitor;
    final failed = message.status == KerabieMessageStatus.failed;
    final pending = message.status == KerabieMessageStatus.pending;
    final radius = Radius.circular(palette.radius);
    final tail = Radius.circular(palette.radius < 4 ? palette.radius : 4);
    final corners = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: mine ? radius : tail,
      bottomRight: mine ? tail : radius,
    );

    // Text on the visitor's bubble follows that bubble's colour, so a light brand colour gets dark text.
    final onBubble = mine ? palette.onUserBubble : palette.text;
    final textColor = failed ? const Color(0xFFDC2626) : onBubble;
    final decoration = failed
        ? BoxDecoration(
            color: const Color(0x1AEF4444),
            borderRadius: corners,
            border: Border.all(color: const Color(0x59EF4444)),
          )
        : mine
            ? palette.userBubbleDecoration(corners)
            : BoxDecoration(color: palette.agentBubble, borderRadius: corners);

    final bubble = DecoratedBox(
      decoration: decoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && message.senderName != null && message.senderName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(message.senderName!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.accent)),
              ),
            _attachment(textColor, mine),
            if (message.body.isNotEmpty || message.streaming)
              Text.rich(
                TextSpan(
                  children: [
                    for (final seg in linkifySegments(message.body))
                      seg.isLink
                          ? TextSpan(
                              text: seg.text,
                              style: const TextStyle(decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()..onTap = () => openKerabieLink(seg.text),
                            )
                          : TextSpan(text: seg.text),
                    if (message.streaming) WidgetSpan(child: KerabieBlinkingCursor(color: textColor)),
                  ],
                ),
                style: TextStyle(color: textColor, fontSize: 15, height: 1.4, fontFamily: palette.fontFamily),
              ),
            _linkPreview(),
            for (final cite in message.citations) _citation(cite, textColor),
            if (pending)
              KerabieSendingDots(color: mine ? onBubble : palette.subtle)
            else if (failed)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tap to retry ↺', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFDC2626))),
              )
            else if (!message.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Opacity(
                    opacity: mine ? 0.75 : 1,
                    child: Text(
                      '${_time(context)}${mine ? (message.status == KerabieMessageStatus.read ? '  ✓✓' : '  ✓') : ''}',
                      style: TextStyle(fontSize: 10, color: mine ? onBubble : palette.subtle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: pending ? 0.65 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) _avatar(),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                child: GestureDetector(onTap: failed ? onRetry : null, child: bubble),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
