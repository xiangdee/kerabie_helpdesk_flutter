import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../controller.dart';
import '../knowledge_base.dart';
import '../provider.dart';
import 'links.dart';
import 'palette.dart';
import 'screen_header.dart';
import 'skeleton.dart';

/// The help centre: search the organisation's knowledge base and read an article.
class KerabieKnowledgeBaseScreen extends StatefulWidget {
  const KerabieKnowledgeBaseScreen({super.key, this.onClose});

  /// Called by the Close button. Defaults to leaving the current route.
  final VoidCallback? onClose;

  @override
  State<KerabieKnowledgeBaseScreen> createState() => _KerabieKnowledgeBaseScreenState();
}

class _KerabieKnowledgeBaseScreenState extends State<KerabieKnowledgeBaseScreen> {
  KerabieKnowledgeBase? _kb;
  final _query = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _kb ??= KerabieKnowledgeBase(KerabieProvider.of(context, listen: false));
  }

  @override
  void dispose() {
    _kb?.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final kb = _kb!;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            KerabieScreenHeader(title: 'Help', palette: palette, onClose: widget.onClose),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                onChanged: kb.search,
                style: TextStyle(color: palette.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search for help',
                  hintStyle: TextStyle(color: palette.subtle),
                  filled: true,
                  fillColor: palette.inputBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.border)),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: kb,
                builder: (_, __) {
                  if (kb.loading) {
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (var i = 0; i < 4; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KerabieSkeleton(color: palette.surfaceStrong, width: 40, height: 40),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.9, child: KerabieSkeleton(color: palette.surfaceStrong, height: 13)),
                                      const SizedBox(height: 6),
                                      FractionallySizedBox(widthFactor: 0.4, child: KerabieSkeleton(color: palette.surfaceStrong, height: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }
                  if (kb.articles.isEmpty) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Text(
                          _query.text.isNotEmpty ? 'No articles match your search.' : 'No articles yet.',
                          style: TextStyle(fontSize: 13, color: palette.subtle),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: kb.articles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final article = kb.articles[i];
                      return InkWell(
                        onTap: () => showKerabieArticleSheet(context, controller, palette, article.id, article.title,
                            content: article.content, imageUrl: article.imageUrl),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: article.imageUrl != null
                                    ? Image.network(article.imageUrl!, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumb(palette))
                                    : _thumb(palette),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(article.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(KerabiePalette palette) => Container(
        width: 40,
        height: 40,
        color: palette.primary.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: const Text('📄', style: TextStyle(fontSize: 18)),
      );
}

/// Reads an article in a bottom sheet. Without [content] (a chat citation only knows the id) the sheet fetches it.
Future<void> showKerabieArticleSheet(
  BuildContext context,
  KerabieController controller,
  KerabiePalette palette,
  int articleId,
  String title, {
  String? content,
  String? imageUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => _ArticleSheet(controller: controller, palette: palette, articleId: articleId, title: title, content: content, imageUrl: imageUrl),
  );
}

class _ArticleSheet extends StatefulWidget {
  const _ArticleSheet({required this.controller, required this.palette, required this.articleId, required this.title, this.content, this.imageUrl});

  final KerabieController controller;
  final KerabiePalette palette;
  final int articleId;
  final String title;
  final String? content;
  final String? imageUrl;

  @override
  State<_ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends State<_ArticleSheet> {
  late String _html = widget.content ?? '';
  late bool _loading = widget.content == null;
  late String? _cover = widget.imageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.content == null) _load();
  }

  Future<void> _load() async {
    final article = await KerabieKnowledgeBase.fetchArticle(widget.controller, widget.articleId);
    if (!mounted) return;
    setState(() {
      _html = article?.content ?? '';
      _cover = article?.imageUrl;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(widget.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35, color: p.text, fontFamily: p.fontFamily)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.text.withValues(alpha: 0.08)),
                  child: Icon(Icons.close_rounded, size: 16, color: p.muted),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_cover != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(_cover!, width: double.infinity, height: 150, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                if (_loading)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: p.accent)))
                else if (_html.isNotEmpty) ...[
                  HtmlWidget(
                    _html,
                    textStyle: TextStyle(color: p.text, fontSize: 14, height: 1.55, fontFamily: p.fontFamily),
                    onTapUrl: (url) {
                      openKerabieLink(url);
                      return true;
                    },
                  ),
                  _ArticleFeedbackRow(controller: widget.controller, palette: p, articleId: widget.articleId),
                ] else
                  Text('Could not load this article.', style: TextStyle(color: p.muted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Was this helpful?" under an article. The vote feeds the helpfulness the team sees in the dashboard.
class _ArticleFeedbackRow extends StatefulWidget {
  const _ArticleFeedbackRow({required this.controller, required this.palette, required this.articleId});

  final KerabieController controller;
  final KerabiePalette palette;
  final int articleId;

  @override
  State<_ArticleFeedbackRow> createState() => _ArticleFeedbackRowState();
}

class _ArticleFeedbackRowState extends State<_ArticleFeedbackRow> {
  late final _feedback = KerabieArticleFeedback(widget.controller);
  bool _loaded = false;
  bool _voted = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _feedback.previousVote(widget.articleId).then((v) {
      if (!mounted) return;
      setState(() {
        _voted = v != null;
        _loaded = true;
      });
    });
  }

  Future<void> _vote(bool helpful) async {
    if (_sending) return;
    setState(() => _sending = true);
    final done = await _feedback.vote(widget.articleId, helpful: helpful);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (done) _voted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final p = widget.palette;
    final style = TextStyle(fontSize: 12.5, color: p.text.withValues(alpha: 0.75));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border, width: 0.5))),
      child: _voted
          ? Text('Thanks for the feedback.', style: style)
          : Row(
              children: [
                Text('Was this helpful?', style: style),
                for (final option in const [('Yes', true), ('No', false)])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Semantics(
                      label: option.$2 ? 'Yes, helpful' : 'No, not helpful',
                      button: true,
                      child: Opacity(
                        opacity: _sending ? 0.5 : 1,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.border),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 28),
                          ),
                          onPressed: _sending ? null : () => _vote(option.$2),
                          child: Text(option.$1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.text)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
