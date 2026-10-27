## 0.3.1

- An article an AI reply cites is now a tappable card like a link preview: the article's picture, its title and the start of its text. The article is fetched once per session.
- The unread count in the conversation list is now right: a conversation counts as read while the customer has it open, and only replies from the team or the AI that came in after that are unread. Needs the matching Kerabie server update (`POST /public/widget/conversations/:id/read`).
- New `controller.markConversationRead(id)`, `controller.loadArticle(id)` and `kerabieArticleExcerpt`.

## 0.3.0

- The chat now opens as the same tabbed widget as the web chat: **Home** (header with logo, status and greeting, search, featured products, suggested articles and an "Ask our AI / Chat with us" card), **Chat**, **Help** and **Tickets** (when the dashboard has them on).
- Chat in the full layout lists the customer's conversations with a **New chat** button; the single layout opens straight on one continuous chat with the whole recent history, and shows the tabs only when "Show navigation" is on.
- Help has the customer's data options and the most useful knowledge base articles as FAQs.
- A tapped notification or `<scheme>://conversation/:id` link opens the widget on that conversation.
- Tapping a featured product opens a sheet with its picture, price, description and a link to the store.
- New controller members: `startNewConversation`, `openConversation`, `conversationsLoaded`. New `KerabieChatSettings` fields from the dashboard: `logoUrl`, `showNavigation`, `showGreeting`, `greetingText`, `showStatusChip`, `statusChipText`, `chatHistoryEnabled`.
- New `KerabieWidget` is what `KerabieChat.show` presents; `KerabieChatScreen` is now just the conversation (with `onBack` and `embedded` for building your own navigation).
- Real icons instead of emoji for attachments, the emoji button, articles, products and the AI avatar.
- Breaking: the settings menu no longer has Change name (the app identifies the customer with `setUser`; anonymous visitors give their name in the pre-chat form), and the chat's settings gear is gone: settings live in the Help tab.
- Breaking: in `openMode: push`, show a `KerabieWidget` (or `KerabieChatScreen`) in your own route.

## 0.2.1

- Agents see whether the customer is on iOS or Android next to the app version.
- Removed the `baseUrl` option: the SDK always talks to Kerabie.

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
