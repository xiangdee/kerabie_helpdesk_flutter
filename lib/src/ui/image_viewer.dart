import 'dart:io';

import 'package:flutter/material.dart';

/// Shows an image full screen. Tap it, or the cross, to close.
Future<void> showKerabieImageViewer(BuildContext context, String source) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xEB000000),
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(ctx).pop(),
            // A cacheWidth keeps a 25 MB camera photo from being decoded at full size.
            child: InteractiveViewer(child: Center(child: _image(source, MediaQuery.sizeOf(ctx).width))),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(ctx).top + 12,
          right: 20,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: const Color(0x26FFFFFF)),
            tooltip: 'Close',
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

Widget _image(String source, double width) {
  final cacheWidth = (width * 2).round();
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Image.network(source, fit: BoxFit.contain, cacheWidth: cacheWidth);
  }
  return Image.file(File(source), fit: BoxFit.contain, cacheWidth: cacheWidth);
}
