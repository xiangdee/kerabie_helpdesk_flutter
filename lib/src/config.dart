import 'package:flutter/material.dart';

import 'models.dart';

/// Where the SDK talks to. Change it only for a self-hosted or staging backend.
const String kerabieDefaultBaseUrl = 'https://api.kerabie.com';

/// How the chat opens. [modal] is a full-screen page, [sheet] a bottom sheet over your app, and [push] hands the
/// opening to your own navigator through [KerabieProvider.onNavigate] (without that callback it opens as [modal]).
enum KerabieOpenMode { modal, sheet, push }

/// Where the launcher sits.
enum KerabiePosition { bottomRight, bottomLeft, topRight, topLeft }

/// `full` has the settings menu; `single` is one continuous chat (the menu shows only when [KerabieChatSettings.showMenu]).
enum KerabieLayout { full, single }

/// The floating button, or a search bar that starts a chat from the text typed into it.
enum KerabieLauncherType { bubble, searchbar }

/// Where [KerabieProvider.onNavigate] should take the app.
enum KerabieRouteType { conversation, inbox }

@immutable
class KerabieRoute {
  const KerabieRoute(this.type, {this.conversationId});

  final KerabieRouteType type;

  /// Set when [type] is [KerabieRouteType.conversation].
  final int? conversationId;
}

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
    this.openMode = KerabieOpenMode.modal,
    this.position = KerabiePosition.bottomRight,
    this.defaultOpen = false,
    this.hideFloatingButton = false,
    this.chatSettings = const KerabieChatSettings(),
  });

  /// From the Kerabie dashboard: Settings, Widget. Starts with `wk_`.
  final String widgetKey;

  /// The app's name, version and build number, sent with the connection.
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

  final KerabieOpenMode openMode;

  /// Where [KerabieLauncher] sits unless you give it an alignment.
  final KerabiePosition position;

  /// Open the chat as soon as the app has built its first frame.
  final bool defaultOpen;

  /// Makes [KerabieLauncher] draw nothing. Open the chat from your own button with [KerabieChat.show].
  final bool hideFloatingButton;

  /// Overrides for what the dashboard saved. Anything left unset follows the dashboard.
  final KerabieChatSettings chatSettings;
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
    this.bubbleIcon,
    this.bubbleSize,
    this.bubbleIconSize,
    this.fontFamily,
    this.chatbotAvatarUrl,
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

  /// Your own picture for the launcher button. Wins over the icon saved in the dashboard.
  final ImageProvider? bubbleIcon;

  /// Diameter of the launcher button.
  final double? bubbleSize;

  /// Size of the icon inside the launcher button.
  final double? bubbleIconSize;

  /// Font used by all text in the chat. The app's own font when unset.
  final String? fontFamily;

  /// The picture beside the AI assistant's replies. Wins over the one saved in the dashboard.
  final String? chatbotAvatarUrl;
}

/// One question on the pre-chat form (dashboard: Messages, Pre-chat form). `name`, `email` and `phone` are the
/// contact's own fields; every other key becomes a custom attribute.
@immutable
class KerabieEnrichmentField {
  const KerabieEnrichmentField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.placeholder,
    this.options = const [],
  });

  final String key;
  final String label;

  /// `text`, `email`, `phone`, `number`, `textarea` or `select`.
  final String type;
  final bool required;
  final String? placeholder;
  final List<String> options;

  static KerabieEnrichmentField? fromServer(Object? raw) {
    if (raw is! Map || raw['key'] is! String || raw['label'] is! String) return null;
    return KerabieEnrichmentField(
      key: raw['key'] as String,
      label: raw['label'] as String,
      type: raw['type'] is String ? raw['type'] as String : 'text',
      required: raw['required'] == true,
      placeholder: raw['placeholder'] as String?,
      options: raw['options'] is List ? (raw['options'] as List).whereType<String>().toList() : const [],
    );
  }
}

/// Chat behaviour. Each field you leave null follows the dashboard (Settings, Widget); each one you set wins.
@immutable
class KerabieChatSettings {
  const KerabieChatSettings({
    this.name,
    this.welcomeMessage,
    this.offlineMessage,
    this.showBranding,
    this.typingIndicator,
    this.enableFileAttachments,
    this.chatbotEnabled,
    this.layout,
    this.showMenu,
    this.launcherType,
    this.searchbarPlaceholder,
    this.customerEnrichmentEnabled,
    this.customerEnrichmentForm,
  });

  /// The title in the chat header.
  final String? name;

  /// Shown before the first message. `{{name}}` becomes the identified user's first name (dropped when unknown).
  final String? welcomeMessage;
  final String? offlineMessage;
  final bool? showBranding;

  /// Show the "agent is typing" indicator.
  final bool? typingIndicator;

  /// Whether visitors can attach a photo or a file. On unless you turn it off.
  final bool? enableFileAttachments;

  /// Whether the AI assistant can reply when no agent is online. Without it, the offline form asks for contact details.
  final bool? chatbotEnabled;
  final KerabieLayout? layout;
  final bool? showMenu;
  final KerabieLauncherType? launcherType;
  final String? searchbarPlaceholder;

  /// Ask visitors the pre-chat questions before their first message.
  final bool? customerEnrichmentEnabled;
  final List<KerabieEnrichmentField>? customerEnrichmentForm;

  /// These settings with every non-null field of [other] on top.
  KerabieChatSettings merge(KerabieChatSettings other) => KerabieChatSettings(
        name: other.name ?? name,
        welcomeMessage: other.welcomeMessage ?? welcomeMessage,
        offlineMessage: other.offlineMessage ?? offlineMessage,
        showBranding: other.showBranding ?? showBranding,
        typingIndicator: other.typingIndicator ?? typingIndicator,
        enableFileAttachments: other.enableFileAttachments ?? enableFileAttachments,
        chatbotEnabled: other.chatbotEnabled ?? chatbotEnabled,
        layout: other.layout ?? layout,
        showMenu: other.showMenu ?? showMenu,
        launcherType: other.launcherType ?? launcherType,
        searchbarPlaceholder: other.searchbarPlaceholder ?? searchbarPlaceholder,
        customerEnrichmentEnabled: other.customerEnrichmentEnabled ?? customerEnrichmentEnabled,
        customerEnrichmentForm: other.customerEnrichmentForm ?? customerEnrichmentForm,
      );
}

/// What the dashboard has saved for this widget (Settings, Widget), fetched when the SDK starts.
@immutable
class KerabieSettings {
  const KerabieSettings({
    this.chat = const KerabieChatSettings(),
    this.primaryColor,
    this.secondaryColor,
    this.gradient = true,
    this.cornerRadius,
    this.borderRadius,
    this.mode = KerabieThemeMode.light,
    this.launcherIconUrl,
    this.launcherIconSize,
    this.chatbotAvatarUrl,
    this.ticketsEnabled = false,
    this.callsEnabled = false,
    this.videoCallsEnabled = false,
  });

  /// The chat behaviour saved in the dashboard. Only what the server sent is set.
  final KerabieChatSettings chat;
  final Color? primaryColor;
  final Color? secondaryColor;
  final bool gradient;
  final double? cornerRadius;

  /// The dashboard's own name for the corner radius: `none`, `small`, `medium` or `large`.
  final String? borderRadius;

  /// The dashboard's Theme setting.
  final KerabieThemeMode mode;

  /// A custom picture for the launcher button, and the size of the icon inside it.
  final String? launcherIconUrl;
  final double? launcherIconSize;

  /// The picture shown beside the AI assistant's replies.
  final String? chatbotAvatarUrl;

  /// Tickets are on in the dashboard, so the app can show an entry point to them.
  final bool ticketsEnabled;

  /// Calls are on in the dashboard and the plan still has minutes. The `kerabie_helpdesk_flutter_calls` package uses it.
  final bool callsEnabled;
  final bool videoCallsEnabled;

  factory KerabieSettings.fromServer(Map<String, dynamic> s) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    String? url(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    bool? flag(Object? v) => v is bool ? v : null;
    final form = s['customerEnrichmentForm'];
    final fields = form is Map && form['fields'] is List
        ? (form['fields'] as List).map(KerabieEnrichmentField.fromServer).whereType<KerabieEnrichmentField>().toList()
        : null;
    return KerabieSettings(
      chat: KerabieChatSettings(
        name: text(s['name']),
        welcomeMessage: text(s['welcomeMessage']),
        offlineMessage: text(s['offlineMessage']),
        showBranding: flag(s['showBranding']),
        typingIndicator: flag(s['typingIndicator']),
        chatbotEnabled: flag(s['chatbotEnabled']),
        layout: switch (s['layout']) {
          'full' => KerabieLayout.full,
          'single' => KerabieLayout.single,
          _ => null,
        },
        showMenu: flag(s['showMenu']),
        launcherType: switch (s['launcherType']) {
          'bubble' => KerabieLauncherType.bubble,
          'searchbar' => KerabieLauncherType.searchbar,
          _ => null,
        },
        searchbarPlaceholder: text(s['searchbarPlaceholder']),
        customerEnrichmentEnabled: flag(s['customerEnrichmentEnabled']),
        customerEnrichmentForm: fields,
      ),
      ticketsEnabled: s['ticketsEnabled'] == true,
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
      primaryColor: parseHexColor(s['primaryColor'] as String?),
      secondaryColor: parseHexColor(s['secondaryColor'] as String?),
      gradient: s['colorType'] != 'singleColor',
      borderRadius: switch (s['borderRadius']) {
        'none' || 'small' || 'medium' || 'large' => s['borderRadius'] as String,
        _ => null,
      },
      cornerRadius: switch (s['borderRadius']) {
        'none' => 0,
        'small' => 8,
        'medium' => 18,
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
