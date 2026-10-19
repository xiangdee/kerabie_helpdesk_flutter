/// Opening the chat from outside the app: a link or a tapped notification.
///
/// The link format is the same in every Kerabie SDK: `<your-scheme>://conversation/<id>`.
/// Notifications from Kerabie carry `conversationId` (and `orgId`) in their data, so a tap needs no URL at all.
class KerabieDeepLink {
  const KerabieDeepLink._();

  /// The conversation id in a `<scheme>://conversation/<id>` link, or null for any other link.
  /// With [scheme] set, links using a different scheme are ignored.
  static int? conversationId(Uri uri, {String? scheme}) {
    if (scheme != null && uri.scheme != scheme) return null;
    if (uri.host != 'conversation' || uri.pathSegments.isEmpty) return null;
    return int.tryParse(uri.pathSegments.first);
  }

  /// `myapp://conversation/123`, for example to put in a notification's `data.url`.
  static Uri conversationUri(int conversationId, String scheme) {
    return Uri(scheme: scheme, host: 'conversation', path: '/$conversationId');
  }

  /// The conversation a notification points at, from its `data` map. Values may arrive as numbers or strings,
  /// because push services deliver data as strings.
  static int? conversationIdFromNotification(Map<String, dynamic> data) {
    final raw = data['conversationId'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
