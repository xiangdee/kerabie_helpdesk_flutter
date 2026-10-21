## 0.2.0

- Photos and files in the chat: pick one, it uploads in the background, and it goes out with your caption. Images open full screen.
- An emoji picker with search and recently used emoji.
- Link previews under messages, read ticks, and links to the knowledge base articles an AI reply used.
- A pre-chat form for contact details: the questions you set in the dashboard, or a name and email form when nobody is online and the AI is off.
- A settings menu in the chat: change name, share or email the transcript, download or erase the customer's data.
- The search bar launcher, and `KerabieLauncher` now draws the floating button or the search bar, whichever the dashboard picked.
- Ready-made screens: `KerabieKnowledgeBaseScreen` (search and article feedback), `KerabieStoreScreen`, `KerabieTicketsScreen` and `KerabieTicketDetailScreen`.
- Campaigns: proactive messages from the dashboard appear above the launcher, limited to screens, audiences and frequencies, and their results are counted.
- `KerabieNavigatorObserver` and `trackScreen` tell Kerabie which screen the customer is on.
- `setUser`, `clearUser`, `updateAttribute` and `setAppVersion` change who the customer is while the app runs.
- `openWithContext` opens the chat and tells the agent what the customer was looking at; `openWithDraft` hands text to the chat.
- `openMode` (`modal`, `sheet`, `push` with `onNavigate`), `position`, `defaultOpen`, `hideFloatingButton`, `onOpenChat`, `onCloseChat` and `onOpenKnowledgeBase`.
- `KerabieChatSettings` overrides what the dashboard saved: title, welcome message, branding, typing indicator, attachments, layout, menu, launcher and pre-chat form. The welcome message can use `{{name}}`.
- More `KerabieTheme` options: `bubbleIcon`, `bubbleSize`, `bubbleIconSize`, `fontFamily` and `chatbotAvatarUrl`.
- A message sent while the connection is down fails at once and can be tapped to send again. The first message of a conversation no longer lets a second one start another conversation.
- The chat shows a reconnecting banner after a drop of three seconds, and replies missed while offline count as unread.
- Breaking: the dashboard's chat values moved from `KerabieSettings` into `KerabieSettings.chat` (`settings.chat.name`, `settings.chat.welcomeMessage`, `settings.chat.showBranding`). `controller.chat` gives the values in force. The welcome message shows only while the conversation is empty.
- On iOS, add `NSPhotoLibraryUsageDescription` to `Info.plist` so customers can attach photos.

## 0.1.0

- First release: `KerabieProvider`, `KerabieLauncher`, `KerabieChat.show` and `KerabieController`.
- Real-time chat that lands in your Kerabie inbox.
- Chat history, user identification, unread count, typing indicators and streamed AI replies.
- Colours, theme mode, widget name and welcome message follow the settings saved in the Kerabie dashboard.
- The requests and events behind voice and video calls, used by the optional `kerabie_helpdesk_flutter_calls` package.
- The custom launcher icon, its size and the AI assistant picture set in the dashboard.
- Light, dark or automatic theme, set in the dashboard or with `KerabieTheme.mode`.
- Text on coloured backgrounds is dark or white by luminance, so it stays readable on any brand colour.
- `KerabieTheme` overrides: `mode`, `backgroundColor`, `textColor`, `agentBubbleColor`, `userBubbleColor`, `bubbleColor`.
