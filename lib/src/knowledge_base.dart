import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'controller.dart';

/// One published article of the organisation's knowledge base.
@immutable
class KerabieArticle {
  const KerabieArticle({required this.id, required this.title, this.content = '', this.imageUrl});

  final int id;
  final String title;

  /// HTML.
  final String content;
  final String? imageUrl;

  static KerabieArticle? fromServer(Object? raw) {
    if (raw is! Map || raw['id'] is! num) return null;
    return KerabieArticle(
      id: (raw['id'] as num).toInt(),
      title: '${raw['title'] ?? ''}',
      content: '${raw['content'] ?? ''}',
      imageUrl: raw['imageUrl'] is String && (raw['imageUrl'] as String).isNotEmpty ? raw['imageUrl'] as String : null,
    );
  }
}

/// The start of an article's text for a card: tags dropped, entities decoded, whitespace collapsed.
String kerabieArticleExcerpt(String html, {int max = 140}) {
  var text = html.replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ').replaceAll(RegExp(r'<[^>]+>'), ' ');
  // Twice: crawled and pasted content is often encoded twice (&amp;nbsp;).
  for (var i = 0; i < 2; i++) {
    text = text
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
        .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll(RegExp(r'&(#39|apos);', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
  }
  text = text.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim();
  return text.length > max ? '${text.substring(0, max).trimRight()}...' : text;
}

/// The searchable knowledge base: the published articles of this widget's organisation, with a debounced search.
/// Articles are remembered on the device, so the list shows at once next time and refreshes behind it.
class KerabieKnowledgeBase extends ChangeNotifier {
  KerabieKnowledgeBase(this._controller, {this.searchDelay = const Duration(milliseconds: 400)}) {
    _start();
  }

  final KerabieController _controller;
  final Duration searchDelay;

  List<KerabieArticle> _articles = const [];
  // True until the first answer (or remembered content) is in, so the screen never flashes "No articles yet."
  bool _loading = true;
  bool _gotFresh = false;
  bool _disposed = false;
  Timer? _timer;

  List<KerabieArticle> get articles => _articles;
  bool get loading => _loading;

  String get _cacheKey => 'cache:kb:${_controller.config.widgetKey}';

  Future<void> _start() async {
    // Remembered articles paint at once; the request below refreshes them.
    final remembered = await _controller.storage.read<List<dynamic>>(_cacheKey);
    if (remembered != null && !_gotFresh && !_disposed) {
      _articles = remembered.map(KerabieArticle.fromServer).whereType<KerabieArticle>().toList();
      _loading = false;
      _notify();
    }
    await refetch();
  }

  Future<void> refetch([String? search]) async {
    final query = search?.trim() ?? '';
    // A search replaces the list so it shows the skeleton; refreshing the default list behind remembered articles does not.
    if (query.isNotEmpty || _articles.isEmpty) {
      _loading = true;
      _notify();
    }
    try {
      final api = await _controller.waitForApi();
      final res = await api.get('/public/kb/articles', query: query.isEmpty ? null : {'search': query});
      final raw = res['data'] is List ? res['data'] as List : const [];
      _articles = raw.map(KerabieArticle.fromServer).whereType<KerabieArticle>().toList();
      if (query.isEmpty) {
        _gotFresh = true;
        unawaited(_controller.storage.write(_cacheKey, raw));
      }
    } on KerabieException {
      // Keep the articles we have.
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Searches after the visitor stops typing.
  void search(String query) {
    _timer?.cancel();
    _timer = Timer(searchDelay, () => refetch(query));
  }

  Future<KerabieArticle?> getArticle(int id) => fetchArticle(_controller, id);

  /// One article with its full body, or null when it cannot be loaded.
  static Future<KerabieArticle?> fetchArticle(KerabieController controller, int id) async {
    try {
      final api = await controller.waitForApi();
      final res = await api.get('/public/kb/articles/$id');
      return KerabieArticle.fromServer(res['article']);
    } on KerabieException {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Records "was this helpful?" for an article. Asked once per article, remembered on the device.
class KerabieArticleFeedback {
  KerabieArticleFeedback(this._controller);

  final KerabieController _controller;

  String _key(int id) => 'kb-vote:$id';

  /// The earlier vote, or null if the visitor has not voted.
  Future<bool?> previousVote(int articleId) => _controller.storage.read<bool>(_key(articleId));

  /// Sends a vote. Returns true when it counts as done: sent, or the server says this visitor voted plenty already.
  Future<bool> vote(int articleId, {required bool helpful}) async {
    try {
      final api = await _controller.waitForApi();
      await api.post('/public/kb/articles/$articleId/feedback', {'helpful': helpful});
      await _controller.storage.write(_key(articleId), helpful);
      return true;
    } on KerabieException catch (e) {
      // Too many votes today (429) counts as done. Anything else lets the visitor try again.
      return e.status == 429 || e.message.toLowerCase().contains('already');
    }
  }
}
