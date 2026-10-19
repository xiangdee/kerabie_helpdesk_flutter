/// Embed the Kerabie help desk in a Flutter app.
///
/// Wrap your app in [KerabieProvider], add a [KerabieLauncher], and customers can message you from any screen.
library;

export 'src/api_client.dart' show KerabieException;
export 'src/config.dart' show KerabieConfig, KerabieSettings, KerabieTheme, KerabieThemeMode, kerabieDefaultBaseUrl;
export 'src/controller.dart' show KerabieController, KerabiePushProvider;
export 'src/deep_link.dart' show KerabieDeepLink;
export 'src/models.dart' show KerabieCallEvent, KerabieCallJoin, KerabieMessage, KerabieMessageStatus, KerabieSender, KerabieUser;
export 'src/provider.dart' show KerabieProvider, KerabieScope;
export 'src/ui/chat_screen.dart' show KerabieChat, KerabieChatScreen;
export 'src/ui/launcher.dart' show KerabieLauncher, KerabieLauncherButton;
export 'src/ui/message_bubble.dart' show KerabieMessageBubble;
export 'src/ui/palette.dart' show KerabiePalette;
