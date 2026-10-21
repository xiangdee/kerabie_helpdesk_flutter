import 'package:flutter/material.dart';

import 'palette.dart';

/// A small in-app dialog in the chat's colours: a title, a body and buttons along the bottom.
Future<T?> showKerabieDialog<T>({
  required BuildContext context,
  required KerabiePalette palette,
  required String title,
  required WidgetBuilder body,
  required List<Widget> Function(BuildContext) actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => KerabieDialogShell(palette: palette, title: title, body: body(ctx), actions: actions(ctx)),
  );
}

/// The frame of a Kerabie dialog. Use it inside your own `showDialog` when the dialog has state of its own.
class KerabieDialogShell extends StatelessWidget {
  const KerabieDialogShell({super.key, required this.palette, required this.title, required this.body, required this.actions});

  final KerabiePalette palette;
  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: palette.background,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: palette.border, width: 0.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.text, fontFamily: palette.fontFamily)),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: palette.muted)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            body,
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The two buttons most dialogs end with.
class KerabieDialogButton extends StatelessWidget {
  const KerabieDialogButton({super.key, required this.label, required this.onPressed, required this.palette, this.color, this.textColor, this.outlined = false});

  final String label;
  final VoidCallback? onPressed;
  final KerabiePalette palette;
  final Color? color;
  final Color? textColor;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: outlined ? Colors.transparent : (color ?? palette.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: outlined ? BorderSide(color: palette.border, width: 0.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor ?? (outlined ? palette.text : palette.onPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}
