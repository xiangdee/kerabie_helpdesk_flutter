import 'package:flutter/material.dart';

import '../controller.dart';
import '../knowledge_base.dart';
import 'knowledge_base_screen.dart';
import 'palette.dart';
import 'settings_screen.dart';
import 'skeleton.dart';

// Only the top few articles fit this screen's quick-answers role; the full searchable list is Home's job.
const _maxFaqs = 8;

/// The Help tab, same as the web widget's: the options card (name, transcripts, data) and the organisation's most
/// useful articles as FAQs (same articles, same cache as Home).
class KerabieHelpScreen extends StatefulWidget {
  const KerabieHelpScreen({super.key, required this.controller, required this.palette});

  final KerabieController controller;
  final KerabiePalette palette;

  @override
  State<KerabieHelpScreen> createState() => _KerabieHelpScreenState();
}

class _KerabieHelpScreenState extends State<KerabieHelpScreen> {
  late final KerabieKnowledgeBase _kb = KerabieKnowledgeBase(widget.controller);

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  Widget _faqs() {
    final p = widget.palette;
    return ListenableBuilder(
      listenable: _kb,
      builder: (_, __) {
        final faqs = _kb.articles.take(_maxFaqs).toList();
        if (!_kb.loading && faqs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text('FREQUENTLY ASKED QUESTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: p.muted, fontFamily: p.fontFamily)),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: p.background,
                  child: Column(
                    children: [
                      if (_kb.loading && faqs.isEmpty)
                        for (var i = 0; i < 3; i++)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.border, width: 0.5))),
                            child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: i.isOdd ? 0.6 : 0.8, child: KerabieSkeleton(height: 14, color: p.surfaceStrong)),
                          )
                      else
                        for (var i = 0; i < faqs.length; i++)
                          InkWell(
                            onTap: () => showKerabieArticleSheet(context, widget.controller, p, faqs[i].id, faqs[i].title, content: faqs[i].content, imageUrl: faqs[i].imageUrl),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.border, width: 0.5))),
                              child: Row(
                                children: [
                                  Expanded(child: Text(faqs[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.text, fontFamily: p.fontFamily))),
                                  Icon(Icons.chevron_right_rounded, size: 18, color: p.subtle),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return ColoredBox(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(color: p.background, border: Border(bottom: BorderSide(color: p.border, width: 0.5))),
              child: Text('Help & Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.fontFamily)),
            ),
            Expanded(child: KerabieSettingsScreen(controller: widget.controller, palette: p, footer: _faqs())),
          ],
        ),
      ),
    );
  }
}
