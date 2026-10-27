import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import 'palette.dart';
import 'skeleton.dart';

String _formatTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff < const Duration(hours: 24)) {
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  }
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (diff < const Duration(days: 7)) return days[local.weekday - 1];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[local.month - 1]} ${local.day}';
}

/// The Chat tab in the full layout: the visitor's past chats with a New chat button, or a "Start a conversation"
/// prompt when there are none. Same as the web widget's conversations screen.
class KerabieConversationsScreen extends StatefulWidget {
  const KerabieConversationsScreen({super.key, required this.controller, required this.palette, required this.onOpen, required this.onNew});

  final KerabieController controller;
  final KerabiePalette palette;
  final ValueChanged<int> onOpen;
  final VoidCallback onNew;

  @override
  State<KerabieConversationsScreen> createState() => _KerabieConversationsScreenState();
}

class _KerabieConversationsScreenState extends State<KerabieConversationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshConversations();
  }

  Widget _brandButton(String label, VoidCallback onTap, {IconData? icon, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8), double radius = 16}) {
    final p = widget.palette;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: p.gradient ? null : p.primary, gradient: p.brandGradient, borderRadius: BorderRadius.circular(radius)),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: p.onPrimary), const SizedBox(width: 6)],
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.onPrimary, fontFamily: p.fontFamily)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final c = widget.controller;
    final chat = c.chat;
    // With "save chat history" off in the dashboard, past conversations are hidden.
    final list = chat.chatHistoryEnabled == false ? const <KerabieConversation>[] : c.conversations;
    final loading = chat.chatHistoryEnabled != false && !c.conversationsLoaded && list.isEmpty;

    return ColoredBox(
      color: p.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border, width: 0.5))),
              child: Row(
                children: [
                  Expanded(child: Text('Chats', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.fontFamily))),
                  if (list.isNotEmpty) _brandButton('New chat', widget.onNew, icon: Icons.add_rounded),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < 3; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                KerabieSkeleton(width: 44, height: 44, borderRadius: 22, color: p.surfaceStrong),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FractionallySizedBox(widthFactor: i.isOdd ? 0.4 : 0.55, child: KerabieSkeleton(height: 14, color: p.surfaceStrong)),
                                      const SizedBox(height: 8),
                                      FractionallySizedBox(widthFactor: 0.8, child: KerabieSkeleton(height: 12, color: p.surfaceStrong)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface),
                                  child: Icon(Icons.chat_bubble_outline_rounded, size: 30, color: p.accent),
                                ),
                                const SizedBox(height: 14),
                                Text('Start a conversation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.fontFamily)),
                                const SizedBox(height: 6),
                                Text(
                                  'Ask a question and get an answer in seconds. Prefer a person? Just say so and we will hand over.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13.5, height: 1.5, color: p.muted, fontFamily: p.fontFamily),
                                ),
                                const SizedBox(height: 18),
                                _brandButton('Start chat', widget.onNew, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11), radius: 12),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _row(list[i], c),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(KerabieConversation conversation, KerabieController c) {
    final p = widget.palette;
    final avatar = conversation.avatar ?? c.chat.logoUrl;
    final name = conversation.name.isNotEmpty ? conversation.name : (c.chat.name ?? c.appName);
    final preview = conversation.lastMessage.length > 60 ? '${conversation.lastMessage.substring(0, 60)}...' : conversation.lastMessage;
    return InkWell(
      onTap: () => widget.onOpen(conversation.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 44,
                    height: 44,
                    color: p.surface,
                    alignment: Alignment.center,
                    child: avatar != null
                        ? Image.network(avatar, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _letter(name))
                        : _letter(name),
                  ),
                ),
                if (conversation.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E), border: Border.all(color: p.background, width: 2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text, fontFamily: p.fontFamily)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatTime(conversation.lastMessageTime), style: TextStyle(fontSize: 11.5, color: p.subtle, fontFamily: p.fontFamily)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted, fontFamily: p.fontFamily)),
                ],
              ),
            ),
            if (conversation.unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(10)),
                child: Text(conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.onPrimary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _letter(String name) => Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: widget.palette.accent, fontFamily: widget.palette.fontFamily),
      );
}
