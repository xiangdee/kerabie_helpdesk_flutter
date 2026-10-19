import 'package:flutter/material.dart';

import '../config.dart';
import '../controller.dart';

/// The colours of the chat, from the dashboard settings, your [KerabieConfig.theme] and the light or dark mode.
@immutable
class KerabiePalette {
  const KerabiePalette({
    required this.primary,
    required this.secondary,
    required this.gradient,
    required this.radius,
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.agentBubble,
    this.userBubbleColor,
    this.launcherColor,
  });

  final Color primary;
  final Color secondary;
  final bool gradient;
  final double radius;
  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color agentBubble;

  /// Set when the developer pinned the visitor bubble or the launcher to one colour.
  final Color? userBubbleColor;
  final Color? launcherColor;

  /// Text and icon colour that stays readable on the header and the send button.
  Color get onPrimary => contrastText(primary);

  /// Text colour on the visitor's bubble, which follows that bubble's own colour.
  Color get onUserBubble => contrastText(userBubbleColor ?? primary);

  /// Text and icon colour on the launcher.
  Color get onLauncher => contrastText(launcherColor ?? primary);

  /// Default slate to teal.
  static const defaultPrimary = Color(0xFF334155);
  static const defaultSecondary = Color(0xFF0F766E);

  /// Dark or white text, whichever stays readable on [background] (WCAG relative luminance, 0.5 threshold).
  static Color contrastText(Color background) =>
      background.computeLuminance() > 0.5 ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  factory KerabiePalette.of(BuildContext context, KerabieController controller) {
    final settings = controller.settings;
    final theme = controller.config.theme;
    // Developer theme wins over the dashboard, which wins over the defaults (light).
    final mode = theme.mode ?? settings.mode;
    final dark = switch (mode) {
      KerabieThemeMode.dark => true,
      KerabieThemeMode.light => false,
      KerabieThemeMode.auto => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final surface = dark ? const Color(0xFF262F3D) : const Color(0xFFF1F5F9);
    return KerabiePalette(
      primary: theme.primaryColor ?? settings.primaryColor ?? defaultPrimary,
      secondary: theme.secondaryColor ?? settings.secondaryColor ?? defaultSecondary,
      gradient: theme.gradient ?? settings.gradient,
      radius: theme.cornerRadius ?? settings.cornerRadius ?? 16,
      background: theme.backgroundColor ?? (dark ? const Color(0xFF1E2530) : Colors.white),
      surface: surface,
      border: dark ? const Color(0xFF333E4D) : const Color(0xFFE2E8F0),
      text: theme.textColor ?? (dark ? const Color(0xFFE5E7EB) : const Color(0xFF0F172A)),
      muted: dark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B),
      agentBubble: theme.agentBubbleColor ?? surface,
      userBubbleColor: theme.userBubbleColor,
      launcherColor: theme.bubbleColor,
    );
  }

  /// Primary to secondary gradient, or null when the chat uses one flat colour.
  Gradient? get brandGradient =>
      gradient ? LinearGradient(colors: [primary, secondary], begin: Alignment.topLeft, end: Alignment.bottomRight) : null;

  /// Fill for the header.
  Decoration get brandDecoration => BoxDecoration(color: gradient ? null : primary, gradient: brandGradient);

  /// Fill for the visitor's bubbles. A colour pinned by the developer wins over the gradient.
  BoxDecoration userBubbleDecoration(BorderRadius radius) => BoxDecoration(
        color: userBubbleColor ?? (gradient ? null : primary),
        gradient: userBubbleColor == null ? brandGradient : null,
        borderRadius: radius,
      );

  /// Fill for the launcher. A colour pinned by the developer wins over the gradient.
  ShapeDecoration launcherDecoration(List<BoxShadow> shadows) => ShapeDecoration(
        shape: const CircleBorder(),
        shadows: shadows,
        color: launcherColor ?? (gradient ? null : primary),
        gradient: launcherColor == null ? brandGradient : null,
      );
}
