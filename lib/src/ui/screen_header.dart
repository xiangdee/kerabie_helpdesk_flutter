import 'package:flutter/material.dart';

import 'palette.dart';

/// The title row of the help, store and ticket screens: a title on the left and a Close link on the right.
class KerabieScreenHeader extends StatelessWidget {
  const KerabieScreenHeader({super.key, required this.title, required this.palette, this.onClose, this.closeLabel = 'Close'});

  final String title;
  final KerabiePalette palette;

  /// Defaults to leaving the current route.
  final VoidCallback? onClose;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: palette.text, fontFamily: palette.fontFamily)),
          ),
          InkWell(
            onTap: onClose ?? () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(closeLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.accent)),
            ),
          ),
        ],
      ),
    );
  }
}
