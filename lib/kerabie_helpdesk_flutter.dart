/// Embed the Kerabie help desk in a Flutter app.
///
/// Wrap your app in [KerabieProvider], add a [KerabieLauncher], and customers can message you from any screen.
library;

export 'src/api_client.dart' show KerabieException;
export 'src/attachments.dart' show DeviceFilePicker, KerabieAttachmentStaging, KerabieFilePicker, KerabieUploadedAttachment;
export 'src/campaigns.dart' show KerabieCampaign, KerabieCampaigns;
export 'src/config.dart'
    show
        KerabieChatSettings,
        KerabieConfig,
        KerabieEnrichmentField,
        KerabieLauncherType,
        KerabieLayout,
        KerabieOpenMode,
        KerabiePosition,
        KerabieRoute,
        KerabieRouteType,
        KerabieSettings,
        KerabieTheme,
        KerabieThemeMode,
        kerabieDefaultBaseUrl;
export 'src/controller.dart' show KerabieController, KerabiePushProvider, kerabieScreenPath;
export 'src/deep_link.dart' show KerabieDeepLink;
export 'src/knowledge_base.dart' show KerabieArticle, KerabieArticleFeedback, KerabieKnowledgeBase;
export 'src/models.dart'
    show
        KerabieAttachment,
        KerabieCallEvent,
        KerabieCallJoin,
        KerabieChatContext,
        KerabieCitation,
        KerabieConversation,
        KerabieLinkPreview,
        KerabieMessage,
        KerabieMessageStatus,
        KerabiePickedFile,
        KerabieSender,
        KerabieUser;
export 'src/provider.dart' show KerabieProvider, KerabieScope;
export 'src/store.dart' show KerabieProduct, KerabieStore;
export 'src/tickets.dart' show KerabieTicket, KerabieTicketMessage, KerabieTicketPriority, KerabieTicketThread, KerabieTickets;
export 'src/ui/chat_screen.dart' show KerabieChat, KerabieChatScreen, kerabiePersonalize;
export 'src/ui/knowledge_base_screen.dart' show KerabieKnowledgeBaseScreen;
export 'src/ui/launcher.dart' show KerabieLauncher, KerabieLauncherButton, KerabieSearchBar;
export 'src/ui/message_bubble.dart' show KerabieMessageBubble;
export 'src/ui/navigator_observer.dart' show KerabieNavigatorObserver, kerabieChatRouteName;
export 'src/ui/palette.dart' show KerabiePalette;
export 'src/ui/skeleton.dart' show KerabieSkeleton, KerabieSkeletonRows;
export 'src/ui/store_screen.dart' show KerabieStoreScreen;
export 'src/ui/tickets_screen.dart' show KerabieTicketDetailScreen, KerabieTicketsScreen, kerabieAgo, kerabieTicketStatusStyle;
