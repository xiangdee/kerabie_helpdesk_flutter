import 'dart:math' as math;

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
    required this.surfaceStrong,
    required this.subtle,
    required this.inputBackground,
    required this.dark,
    this.userBubbleColor,
    this.launcherColor,
    this.fontFamily,
    this.launcherRadiusFactor = 0.35,
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
  final Color surfaceStrong;

  /// Fainter than [muted]: timestamps and placeholders.
  final Color subtle;
  final Color inputBackground;
  final bool dark;
  final String? fontFamily;

  /// How round the launcher is: 0 is square, 0.5 is a circle.
  final double launcherRadiusFactor;

  /// Set when the developer pinned the visitor bubble or the launcher to one colour.
  final Color? userBubbleColor;
  final Color? launcherColor;

  /// Text and icon colour that stays readable on the header and the send button.
  Color get onPrimary => contrastText(primary);

  /// Text colour on the visitor's bubble, which follows that bubble's own colour.
  Color get onUserBubble => contrastText(userBubbleColor ?? primary);

  /// Text and icon colour on the launcher.
  Color get onLauncher => contrastText(launcherColor ?? primary);

  /// The brand colour made usable as text or an icon on [surfaceStrong]: darkened on a light surface and lightened on a
  /// dark one, just until it reaches WCAG AA (4.5:1). A bright brand colour such as lime is otherwise unreadable.
  Color get accent => readableAccent(primary, surfaceStrong);

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
      radius: theme.cornerRadius ?? settings.cornerRadius ?? 18,
      background: theme.backgroundColor ?? (dark ? const Color(0xFF1E2530) : Colors.white),
      surface: surface,
      border: dark ? const Color(0xFF333E4D) : const Color(0xFFE2E8F0),
      surfaceStrong: dark ? const Color(0xFF2D3746) : const Color(0xFFE2E8F0),
      subtle: dark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8),
      inputBackground: dark ? const Color(0xFF262F3D) : const Color(0xFFF8FAFC),
      dark: dark,
      fontFamily: theme.fontFamily,
      launcherRadiusFactor: launcherRadiusFor(theme.cornerRadius ?? settings.cornerRadius),
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

/// Launcher corner factors by the dashboard's none / small / medium / large: 0, 0.2, 0.35, 0.5 of the button size.
double launcherRadiusFor(double? cornerRadius) {
  if (cornerRadius == null) return 0.35;
  if (cornerRadius <= 0) return 0;
  if (cornerRadius <= 8) return 0.2;
  if (cornerRadius <= 18) return 0.35;
  return 0.5;
}

double _channel(int v) {
  final s = v / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) =>
    0.2126 * _channel((c.r * 255).round()) + 0.7152 * _channel((c.g * 255).round()) + 0.0722 * _channel((c.b * 255).round());

double _contrast(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// [brand] made readable as text or an icon on [surface]: the same hue, darkened on a light surface (lightened on a
/// dark one) just until it reaches [min] contrast, and untouched when it already does.
Color readableAccent(Color brand, Color surface, {double min = 4.5}) {
  final surfaceLum = _luminance(surface);
  if (_contrast(_luminance(brand), surfaceLum) >= min) return brand;
  final light = surfaceLum > 0.5;
  final target = light ? Colors.black : Colors.white;
  for (var t = 0.05; t < 1; t += 0.05) {
    final candidate = Color.lerp(brand, target, t)!;
    if (_contrast(_luminance(candidate), surfaceLum) >= min) return candidate;
  }
  return target;
}
