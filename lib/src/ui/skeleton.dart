import 'package:flutter/material.dart';

/// A shimmering placeholder while content loads.
class KerabieSkeleton extends StatefulWidget {
  const KerabieSkeleton({super.key, this.width, this.height = 16, this.aspectRatio, this.borderRadius = 8, this.color = const Color(0xFFE2E8F0)});

  /// Null fills the available width.
  final double? width;

  /// Ignored when [aspectRatio] is set.
  final double height;
  final double? aspectRatio;
  final double borderRadius;

  /// The base colour. Pass the chat palette's strong surface for the right contrast in light and dark.
  final Color color;

  @override
  State<KerabieSkeleton> createState() => _KerabieSkeletonState();
}

class _KerabieSkeletonState extends State<KerabieSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.4).animate(_controller),
      child: DecoratedBox(decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(widget.borderRadius))),
    );
    if (widget.aspectRatio != null) {
      return SizedBox(width: widget.width, child: AspectRatio(aspectRatio: widget.aspectRatio!, child: box));
    }
    return SizedBox(width: widget.width, height: widget.height, child: box);
  }
}

/// A few lines of [KerabieSkeleton], the last one shorter.
class KerabieSkeletonRows extends StatelessWidget {
  const KerabieSkeletonRows({super.key, this.rows = 3, this.gap = 10, this.color = const Color(0xFFE2E8F0)});

  final int rows;
  final double gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < rows - 1 ? gap : 0),
            child: FractionallySizedBox(
              widthFactor: i == rows - 1 ? 0.65 : 1,
              child: KerabieSkeleton(height: 14, color: color),
            ),
          ),
      ],
    );
  }
}
