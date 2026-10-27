import 'dart:io';

import 'package:flutter/material.dart';

import '../config.dart';
import '../controller.dart';
import '../provider.dart';
import 'chat_screen.dart';
import 'palette.dart';

Alignment _alignmentFor(KerabiePosition position) => switch (position) {
      KerabiePosition.bottomRight => Alignment.bottomRight,
      KerabiePosition.bottomLeft => Alignment.bottomLeft,
      KerabiePosition.topRight => Alignment.topRight,
      KerabiePosition.topLeft => Alignment.topLeft,
    };

/// The launcher the dashboard picked: the floating chat button, or the search bar. Put it in a `Stack` over your
/// screen. It draws nothing when [KerabieConfig.hideFloatingButton] is set. Use [KerabieLauncherButton] or
/// [KerabieSearchBar] where you want to place one yourself.
class KerabieLauncher extends StatelessWidget {
  const KerabieLauncher({super.key, this.alignment, this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 24), this.size});

  /// Where the button sits. Follows [KerabieConfig.position] when null.
  final Alignment? alignment;
  final EdgeInsets margin;

  /// Diameter of the button. Follows [KerabieTheme.bubbleSize] (56 when unset) when null.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    if (controller.config.hideFloatingButton) return const SizedBox.shrink();
    if (controller.chat.launcherType == KerabieLauncherType.searchbar) return const KerabieSearchBar();
    return SafeArea(
      child: Align(
        alignment: alignment ?? _alignmentFor(controller.config.position),
        child: Padding(padding: margin, child: KerabieLauncherButton(size: size)),
      ),
    );
  }
}

/// Just the floating button, with its unread badge. Draws nothing when the dashboard picked the search bar.
class KerabieLauncherButton extends StatelessWidget {
  const KerabieLauncherButton({super.key, this.size, this.badgeColor = const Color(0xFFEF4444)});

  /// Diameter of the button. Follows [KerabieTheme.bubbleSize] (56 when unset) when null.
  final double? size;
  final Color badgeColor;

  /// The icon: your own picture, else the one from the dashboard, else the default chat icon.
  Widget _icon(KerabieController controller, KerabiePalette palette, double diameter) {
    final theme = controller.config.theme;
    final settings = controller.settings;
    final iconSize = theme.bubbleIconSize ?? settings.launcherIconSize ?? diameter * 0.45;
    final fallback = Icon(Icons.chat_bubble_rounded, color: palette.onLauncher, size: iconSize);
    if (theme.bubbleIcon != null) {
      return Image(image: theme.bubbleIcon!, width: iconSize, height: iconSize, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    }
    final url = settings.launcherIconUrl;
    if (url == null) return fallback;
    return Image.network(url, width: iconSize, height: iconSize, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    if (controller.chat.launcherType == KerabieLauncherType.searchbar) return const SizedBox.shrink();
    final palette = KerabiePalette.of(context, controller);
    final diameter = size ?? controller.config.theme.bubbleSize ?? 56;
    final radius = BorderRadius.circular(diameter * palette.launcherRadiusFactor);
    final unread = controller.unreadCount;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Open chat, $unread unread' : 'Open chat',
      child: GestureDetector(
        onTap: () {
          // The button toggles: it opens the chat from the app and takes it away again from an inline chat.
          if (controller.isOpen) {
            controller.dismissChat();
          } else {
            KerabieChat.show(context);
          }
        },
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(borderRadius: radius),
                  shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
                  color: palette.launcherColor ?? (palette.gradient ? null : palette.primary),
                  gradient: palette.launcherColor == null ? palette.brandGradient : null,
                ),
                child: SizedBox.expand(child: Center(child: _icon(controller, palette, diameter))),
              ),
              if (unread > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
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

/// The search bar launcher (dashboard: Launcher, Search bar): a wide "Ask anything…" box docked to the top or bottom
/// of the screen. Sending opens the chat and sends what was typed. A file picked with the paperclip stays in the bar
/// and uploads first, like in the chat's composer. Draws nothing unless the dashboard picked the search bar.
class KerabieSearchBar extends StatefulWidget {
  const KerabieSearchBar({super.key});

  @override
  State<KerabieSearchBar> createState() => _KerabieSearchBarState();
}

class _KerabieSearchBarState extends State<KerabieSearchBar> {
  final _text = TextEditingController();
  bool _chooser = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(KerabieController controller) {
    if (controller.staging.isUploading) return;
    final body = _text.text.trim();
    _text.clear();
    if (body.isNotEmpty || controller.staging.pending != null) {
      controller.openWithDraft(body);
    } else {
      KerabieChat.show(context);
    }
  }

  void _pick(KerabieController controller, bool photo) {
    setState(() => _chooser = false);
    photo ? controller.pickPhoto() : controller.pickDocument();
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final config = controller.config;
    if (controller.chat.launcherType != KerabieLauncherType.searchbar || config.hideFloatingButton || controller.isOpen) {
      return const SizedBox.shrink();
    }
    final palette = KerabiePalette.of(context, controller);
    final atTop = config.position == KerabiePosition.topLeft || config.position == KerabiePosition.topRight;
    final staging = controller.staging;

    return SafeArea(
      child: Align(
        alignment: atTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ListenableBuilder(
            listenable: staging,
            builder: (_, __) {
              Widget note(Widget child, {Color? border}) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: palette.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: border ?? palette.border)),
                      child: child,
                    ),
                  );
              final notes = <Widget>[
                if (staging.error != null)
                  note(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(staging.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)))),
                      const SizedBox(width: 8),
                      InkWell(onTap: staging.dismissError, child: Icon(Icons.close_rounded, size: 14, color: palette.muted)),
                    ]),
                    border: const Color(0xFFFCA5A5),
                  ),
                if (_chooser)
                  note(Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => _pick(controller, true), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image_outlined, size: 18, color: palette.text), const SizedBox(width: 8), Text('Photo', style: TextStyle(color: palette.text))])),
                    TextButton(onPressed: () => _pick(controller, false), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.description_outlined, size: 18, color: palette.text), const SizedBox(width: 8), Text('Document', style: TextStyle(color: palette.text))])),
                  ])),
                if (staging.pending != null)
                  note(Row(mainAxisSize: MainAxisSize.min, children: [
                    if (staging.pending!.isImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image(image: ResizeImage(FileImage(File(staging.pending!.path)), width: 96), width: 32, height: 32, fit: BoxFit.cover),
                      )
                    else
                      Icon(Icons.attach_file_rounded, size: 20, color: palette.muted),
                    const SizedBox(width: 8),
                    Flexible(child: Text(staging.pending!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.text))),
                    const SizedBox(width: 8),
                    if (staging.isUploading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    InkWell(onTap: staging.remove, child: Icon(Icons.close_rounded, size: 14, color: palette.muted)),
                  ])),
              ];
              final bar = Container(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: palette.border),
                  boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Send attachment',
                      onPressed: staging.pending != null ? null : () => setState(() => _chooser = !_chooser),
                      icon: Icon(Icons.attach_file_rounded, size: 20, color: palette.muted),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(controller),
                        style: TextStyle(color: palette.text, fontSize: 15, fontFamily: palette.fontFamily),
                        decoration: InputDecoration(
                          hintText: controller.chat.searchbarPlaceholder ?? 'Ask anything...',
                          hintStyle: TextStyle(color: palette.subtle),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: staging.isUploading ? 0.5 : 1,
                      child: Semantics(
                        button: true,
                        label: 'Start chat',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: staging.isUploading ? null : () => _submit(controller),
                          child: Ink(
                            width: 40,
                            height: 40,
                            decoration: ShapeDecoration(shape: const CircleBorder(), color: palette.gradient ? null : palette.primary, gradient: palette.brandGradient),
                            child: Icon(Icons.arrow_forward_rounded, size: 20, color: palette.onPrimary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (atTop) bar,
                  for (final n in notes) Padding(padding: EdgeInsets.only(top: atTop ? 8 : 0, bottom: atTop ? 0 : 8), child: n),
                  if (!atTop) bar,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
