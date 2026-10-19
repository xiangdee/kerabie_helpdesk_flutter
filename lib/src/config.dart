import 'package:flutter/material.dart';

import 'models.dart';

/// Where the SDK talks to. Change it only for a self-hosted or staging backend.
const String kerabieDefaultBaseUrl = 'https://api.kerabie.com';

/// Everything the SDK needs to start.
@immutable
class KerabieConfig {
  const KerabieConfig({
    required this.widgetKey,
    required this.appName,
    required this.appVersion,
    this.appBuild = '',
    this.user,
    this.theme = const KerabieTheme(),
    this.deepLinkScheme,
    this.baseUrl = kerabieDefaultBaseUrl,
  });

  /// From the Kerabie dashboard: Settings, Widget. Starts with `wk_`.
  final String widgetKey;

  /// Shown to agents in the conversation, so they know which app the customer is using.
  final String appName;
  final String appVersion;
  final String appBuild;
  final KerabieUser? user;

  /// Overrides for the colours saved in the dashboard. Anything left unset follows the dashboard.
  final KerabieTheme theme;

  /// Your app's URL scheme, for example `myapp`. When set, only `myapp://conversation/123` links open the chat;
  /// when null a conversation link with any scheme opens it.
  final String? deepLinkScheme;
  final String baseUrl;
}

/// Light or dark chat. [auto] follows the device. The dashboard's Theme setting uses the same three values.
enum KerabieThemeMode { light, dark, auto }

/// Local overrides for the look of the chat. Anything left unset follows the dashboard.
@immutable
class KerabieTheme {
  const KerabieTheme({
    this.primaryColor,
    this.secondaryColor,
    this.gradient,
    this.cornerRadius,
    this.mode,
    this.backgroundColor,
    this.textColor,
    this.agentBubbleColor,
    this.userBubbleColor,
    this.bubbleColor,
  });

  final Color? primaryColor;
  final Color? secondaryColor;

  /// Use a primary to secondary gradient on the header and launcher.
  final bool? gradient;
  final double? cornerRadius;

  /// Light, dark or follow the device. When unset the dashboard's Theme setting decides, and light if that is unset too.
  final KerabieThemeMode? mode;

  /// Replace the chat background and text colour of the light or dark scheme.
  final Color? backgroundColor;
  final Color? textColor;
  final Color? agentBubbleColor;

  /// The visitor's own bubbles. Setting it turns off the gradient on them.
  final Color? userBubbleColor;

  /// The launcher button. Setting it turns off the gradient on it.
  final Color? bubbleColor;
}

/// What the dashboard has saved for this widget (Settings, Widget), fetched when the SDK starts.
@immutable
class KerabieSettings {
  const KerabieSettings({
    this.name,
    this.welcomeMessage,
    this.offlineMessage,
    this.primaryColor,
    this.secondaryColor,
    this.gradient = true,
    this.showBranding = true,
    this.chatbotEnabled = true,
    this.cornerRadius,
    this.mode = KerabieThemeMode.light,
    this.launcherIconUrl,
    this.launcherIconSize,
    this.chatbotAvatarUrl,
    this.callsEnabled = false,
    this.videoCallsEnabled = false,
  });

  final String? name;
  final String? welcomeMessage;
  final String? offlineMessage;
  final Color? primaryColor;
  final Color? secondaryColor;
  final bool gradient;
  final bool showBranding;
  final bool chatbotEnabled;
  final double? cornerRadius;

  /// The dashboard's Theme setting.
  final KerabieThemeMode mode;

  /// A custom picture for the launcher button, and the size of the icon inside it.
  final String? launcherIconUrl;
  final double? launcherIconSize;

  /// The picture shown beside the AI assistant's replies.
  final String? chatbotAvatarUrl;

  /// Calls are on in the dashboard and the plan still has minutes. The `kerabie_helpdesk_flutter_calls` package uses it.
  final bool callsEnabled;
  final bool videoCallsEnabled;

  factory KerabieSettings.fromServer(Map<String, dynamic> s) {
    String? url(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    return KerabieSettings(
      callsEnabled: s['callsEnabled'] == true,
      videoCallsEnabled: s['videoCallsEnabled'] == true,
      launcherIconUrl: url(s['launcherIconUrl']),
      launcherIconSize: s['launcherIconSize'] is num ? (s['launcherIconSize'] as num).toDouble() : null,
      chatbotAvatarUrl: url(s['chatbotAvatarUrl']),
      mode: switch (s['theme']) {
        'dark' => KerabieThemeMode.dark,
        'auto' => KerabieThemeMode.auto,
        _ => KerabieThemeMode.light,
      },
      name: s['name'] as String?,
      welcomeMessage: s['welcomeMessage'] as String?,
      offlineMessage: s['offlineMessage'] as String?,
      primaryColor: parseHexColor(s['primaryColor'] as String?),
      secondaryColor: parseHexColor(s['secondaryColor'] as String?),
      gradient: s['colorType'] != 'singleColor',
      showBranding: s['showBranding'] is bool ? s['showBranding'] as bool : true,
      chatbotEnabled: s['chatbotEnabled'] is bool ? s['chatbotEnabled'] as bool : true,
      cornerRadius: switch (s['borderRadius']) {
        'none' => 0,
        'small' => 8,
        'medium' => 16,
        'large' => 24,
        _ => null,
      },
    );
  }
}

/// Parses `#rgb`, `#rrggbb` or `#aarrggbb`. Returns null for anything else.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'ff$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}
