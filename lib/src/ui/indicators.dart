import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Three bouncing dots: an agent is writing.
class KerabieTypingDots extends StatefulWidget {
  const KerabieTypingDots({super.key, required this.palette});

  final KerabiePalette palette;

  @override
  State<KerabieTypingDots> createState() => _KerabieTypingDotsState();
}

class _KerabieTypingDotsState extends State<KerabieTypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'Typing',
          child: DecoratedBox(
            decoration: BoxDecoration(color: widget.palette.agentBubble, borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
                        child: Transform.translate(
                          offset: Offset(0, -4 * _bounce((_controller.value * 1200 - i * 150) % 1200)),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.palette.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 0 to 1 and back over 600 ms, then rest, like the other SDKs' dots.
  double _bounce(double ms) {
    if (ms >= 600) return 0;
    return ms < 300 ? ms / 300 : (600 - ms) / 300;
  }
}

/// The AI assistant is "thinking": a drop that squashes and stretches while it slowly turns.
class KerabieAiOrb extends StatefulWidget {
  const KerabieAiOrb({super.key, required this.palette});

  final KerabiePalette palette;

  @override
  State<KerabieAiOrb> createState() => _KerabieAiOrbState();
}

class _KerabieAiOrbState extends State<KerabieAiOrb> with TickerProviderStateMixin {
  late final AnimationController _squash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))..repeat();

  @override
  void dispose() {
    _squash.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Semantics(
        label: 'Thinking',
        child: Row(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_squash, _spin]),
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_squash.value);
                return Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: Transform.scale(
                    scaleX: 1.15 + (0.88 - 1.15) * t,
                    scaleY: 0.88 + (1.15 - 0.88) * t,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.primary,
                        gradient: p.brandGradient,
                        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                      ),
                      child: Align(
                        alignment: const Alignment(-0.45, -0.45),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x8CFFFFFF)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Text('Thinking…', style: TextStyle(fontSize: 12, color: p.muted, fontFamily: p.fontFamily)),
          ],
        ),
      ),
    );
  }
}

/// Three pulsing dots at the bottom of a bubble that is being sent.
class KerabieSendingDots extends StatefulWidget {
  const KerabieSendingDots({super.key, required this.color});

  final Color color;

  @override
  State<KerabieSendingDots> createState() => _KerabieSendingDotsState();
}

class _KerabieSendingDotsState extends State<KerabieSendingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 980))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
                child: Opacity(
                  opacity: 0.3 + 0.7 * _pulse((_controller.value * 980 - i * 160) % 980),
                  child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _pulse(double ms) {
    if (ms >= 500) return 0;
    return ms < 250 ? ms / 250 : (500 - ms) / 250;
  }
}

/// The blinking block after an AI reply that is still arriving.
class KerabieBlinkingCursor extends StatefulWidget {
  const KerabieBlinkingCursor({super.key, required this.color});

  final Color color;

  @override
  State<KerabieBlinkingCursor> createState() => _KerabieBlinkingCursorState();
}

class _KerabieBlinkingCursorState extends State<KerabieBlinkingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _controller, child: Text(' ▍', style: TextStyle(color: widget.color, fontSize: 15)));
}
