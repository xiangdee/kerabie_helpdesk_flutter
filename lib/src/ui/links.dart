import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser or the app that handles it. A bad link is ignored.
Future<void> openKerabieLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Nothing on the device can open it; there is nothing useful to show.
  }
}

final _urlPattern = RegExp(r'https?://[^\s]+');

/// Splits message text into plain and link parts so a bare URL can be a tappable link.
List<({String text, bool isLink})> linkifySegments(String text) {
  if (text.isEmpty) return const [];
  final parts = <({String text, bool isLink})>[];
  var last = 0;
  for (final match in _urlPattern.allMatches(text)) {
    if (match.start > last) parts.add((text: text.substring(last, match.start), isLink: false));
    parts.add((text: match.group(0)!, isLink: true));
    last = match.end;
  }
  if (last < text.length) parts.add((text: text.substring(last), isLink: false));
  return parts;
}

/// The host of a link, for the line under a link preview.
String hostnameOf(String url) => Uri.tryParse(url)?.host.isNotEmpty == true ? Uri.parse(url).host : url;
