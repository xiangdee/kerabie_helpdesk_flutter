import 'package:flutter/material.dart';

import '../config.dart';
import '../provider.dart';
import 'chat_screen.dart';
import 'palette.dart';

/// The floating chat button with an unread badge. Put it in a `Stack` over your screen, or use
/// [KerabieLauncherButton] where you want to place it yourself.
class KerabieLauncher extends StatelessWidget {
  const KerabieLauncher({
    super.key,
    this.alignment = Alignment.bottomRight,
    this.margin = const EdgeInsets.all(16),
    this.size = 56,
  });

  final Alignment alignment;
  final EdgeInsets margin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(padding: margin, child: KerabieLauncherButton(size: size)),
      ),
    );
  }
}

/// Just the button.
class KerabieLauncherButton extends StatelessWidget {
  const KerabieLauncherButton({super.key, this.size = 56});

  final double size;

  /// The icon from the dashboard when there is one, else the default chat icon.
  Widget _icon(KerabieSettings settings, KerabiePalette palette) {
    final iconSize = settings.launcherIconSize ?? size * 0.45;
    final fallback = Icon(Icons.chat_bubble_rounded, color: palette.onLauncher, size: iconSize);
    final url = settings.launcherIconUrl;
    if (url == null) return fallback;
    return Image.network(url, width: iconSize, height: iconSize, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final unread = controller.unreadCount;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Open chat, $unread unread' : 'Open chat',
      child: GestureDetector(
        onTap: () => KerabieChat.show(context),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: palette.launcherDecoration(
                  const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: SizedBox.expand(child: Center(child: _icon(controller.settings, palette))),
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
