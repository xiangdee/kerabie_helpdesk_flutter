import 'package:flutter/material.dart';

import '../controller.dart';
import '../knowledge_base.dart';
import '../models.dart';
import 'palette.dart';

/// The article an AI reply matched, as a tappable card like a link preview: the article's picture, its title and the
/// start of its text. The article is fetched once per session, so the same card on several messages costs one request.
class KerabieArticleCard extends StatelessWidget {
  const KerabieArticleCard({super.key, required this.controller, required this.citation, required this.palette, required this.onOpen});

  final KerabieController controller;
  final KerabieCitation citation;
  final KerabiePalette palette;

  /// Called with the article once it has loaded, or null while it has not (the sheet fetches it itself).
  final void Function(KerabieArticle? article) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return FutureBuilder<KerabieArticle?>(
      future: controller.loadArticle(citation.id),
      builder: (context, snapshot) {
        final article = snapshot.data;
        final title = article?.title.isNotEmpty == true ? article!.title : citation.title;
        final excerpt = article == null ? '' : kerabieArticleExcerpt(article.content);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            button: true,
            label: 'Read the article: $title',
            child: GestureDetector(
              onTap: () => onOpen(article),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: p.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.border, width: 0.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (article?.imageUrl != null)
                      Image.network(article!.imageUrl!, width: double.infinity, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3, color: p.text, fontFamily: p.fontFamily)),
                          if (excerpt.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.3, color: p.muted, fontFamily: p.fontFamily)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Row(
                              children: [
                                Icon(Icons.description_outlined, size: 12, color: p.accent),
                                const SizedBox(width: 4),
                                Expanded(child: Text('Help article', style: TextStyle(fontSize: 10, color: p.subtle, fontFamily: p.fontFamily))),
                                Icon(Icons.chevron_right_rounded, size: 14, color: p.subtle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
