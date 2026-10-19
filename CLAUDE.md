# Project Instructions

This package is the Flutter client for the Kerabie chat widget. Keep it in step with the other clients: any change to what the widget does or sends must be mirrored in `react-native-kerabie-helpdesk` (`kerabie\react-native-kerabie-helpdesk`), the web widget (`kerabie\kerabie-chat-widget`) and `kerabie-sdk`.

- Before any design or UI decision, re-read the `Design.md` of `kerabie\react-native-kerabie-helpdesk`; the colours and shapes here mirror it.
- The wire protocol (endpoints, headers, socket events and payloads) is defined by the backend; the React Native SDK in `src/services` is the reference implementation.
- Settings stay manageable from the dashboard (Settings, Widget) and `kerabie-admin`. Never hard-code what the server already sends.
