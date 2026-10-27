import 'package:flutter/material.dart';

import '../controller.dart';
import '../knowledge_base.dart';
import '../store.dart';
import 'chat_screen.dart';
import 'knowledge_base_screen.dart';
import 'palette.dart';
import 'product_sheet.dart';
import 'skeleton.dart';

/// The widget's landing screen, same layout as the web widget's home: a branded header with the greeting, a search
/// box, featured products, suggested articles and the "Ask our AI / Chat with us" card.
class KerabieHomeScreen extends StatefulWidget {
  const KerabieHomeScreen({super.key, required this.controller, required this.palette, required this.onClose, required this.onChat});

  final KerabieController controller;
  final KerabiePalette palette;
  final VoidCallback onClose;
  final VoidCallback onChat;

  @override
  State<KerabieHomeScreen> createState() => _KerabieHomeScreenState();
}

class _KerabieHomeScreenState extends State<KerabieHomeScreen> {
  late final KerabieKnowledgeBase _kb = KerabieKnowledgeBase(widget.controller);
  late final KerabieStore _store = KerabieStore(widget.controller);
  final _query = TextEditingController();

  @override
  void dispose() {
    _kb.dispose();
    _store.dispose();
    _query.dispose();
    super.dispose();
  }

  KerabiePalette get _p => widget.palette;

  Widget _header() {
    final c = widget.controller;
    final chat = c.chat;
    final chatbot = chat.chatbotEnabled == true;
    final agentsOnline = (c.agentsOnline ?? 0) > 0;
    final available = agentsOnline || chatbot;
    final statusText = chat.statusChipText ?? (chatbot ? 'Instant answers' : agentsOnline ? 'We reply in minutes' : "We're offline");
    final name = chat.name ?? c.appName;
    final greeting = kerabiePersonalize(chat.greetingText ?? 'Hello there \u{1F44B}\nGot questions?', c.visitorName);
    final on = _p.onPrimary;

    return DecoratedBox(
      decoration: _p.brandDecoration,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 36,
                      height: 36,
                      color: on,
                      alignment: Alignment.center,
                      child: chat.logoUrl != null
                          ? Image.network(chat.logoUrl!, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _logoLetter(name))
                          : _logoLetter(name),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on, fontFamily: _p.fontFamily)),
                  ),
                  if (chat.showStatusChip != false)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: available ? const Color(0xFF4ADE80) : const Color(0xFFCBD5E1))),
                          const SizedBox(width: 6),
                          Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on, fontFamily: _p.fontFamily)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18)),
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close_rounded, size: 20, color: on),
                  ),
                ],
              ),
              if (chat.showGreeting != false) ...[
                const SizedBox(height: 22),
                Text(greeting, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.22, color: on, fontFamily: _p.fontFamily)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoLetter(String name) => Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _p.primary, fontFamily: _p.fontFamily),
      );

  TextStyle _section() => TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: _p.muted, fontFamily: _p.fontFamily);

  Widget _articles() {
    return ListenableBuilder(
      listenable: _kb,
      builder: (_, __) {
        final searching = _query.text.trim().isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(searching ? 'RESULTS FOR "${_query.text.trim().toUpperCase()}"' : 'SUGGESTED ARTICLES', style: _section()),
            const SizedBox(height: 4),
            if (_kb.loading)
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      KerabieSkeleton(width: 32, height: 32, borderRadius: 8, color: _p.surfaceStrong),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(widthFactor: i.isOdd ? 0.7 : 0.9, child: KerabieSkeleton(height: 13, color: _p.surfaceStrong)),
                            const SizedBox(height: 6),
                            FractionallySizedBox(widthFactor: 0.4, child: KerabieSkeleton(height: 11, color: _p.surfaceStrong)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
            else if (_kb.articles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(searching ? 'No articles match your search.' : 'No articles yet.', style: TextStyle(fontSize: 13, color: _p.subtle, fontFamily: _p.fontFamily))),
              )
            else
              for (final a in _kb.articles)
                InkWell(
                  onTap: () => showKerabieArticleSheet(context, widget.controller, _p, a.id, a.title, content: a.content, imageUrl: a.imageUrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: a.imageUrl != null
                              ? Image.network(a.imageUrl!, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _articleIcon())
                              : _articleIcon(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _p.text, fontFamily: _p.fontFamily)),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: _p.subtle),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _articleIcon() => Container(width: 32, height: 32, color: _p.surface, alignment: Alignment.center, child: Icon(Icons.description_outlined, size: 16, color: _p.accent));

  Widget _products() {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _query]),
      builder: (_, __) {
        if (_query.text.trim().isNotEmpty || _store.products.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FEATURED PRODUCTS', style: _section()),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _store.products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final product = _store.products[i];
                    return InkWell(
                      onTap: () => showKerabieProductSheet(context, _p, product, _store.storeUrl),
                      child: SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 110,
                                height: 110,
                                color: _p.surface,
                                alignment: Alignment.center,
                                child: product.imageUrl != null
                                    ? Image.network(product.imageUrl!, width: 110, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, size: 28, color: _p.subtle))
                                    : Icon(Icons.inventory_2_outlined, size: 28, color: _p.subtle),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _p.text, fontFamily: _p.fontFamily)),
                            Text(product.formattedPrice, style: TextStyle(fontSize: 12, color: _p.muted, fontFamily: _p.fontFamily)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _askCard() {
    final chatbot = widget.controller.chat.chatbotEnabled == true;
    return Material(
      color: _p.background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onChat,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _p.gradient ? null : _p.primary, gradient: _p.brandGradient),
                child: Icon(Icons.auto_awesome_rounded, size: 18, color: _p.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chatbot ? 'Ask our AI' : 'Chat with us', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _p.text, fontFamily: _p.fontFamily)),
                    const SizedBox(height: 2),
                    Text(
                      chatbot ? 'Instant answers, 24/7. A human is one tap away.' : 'Send us a message and we will reply as soon as we can.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: _p.muted, fontFamily: _p.fontFamily),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: _p.subtle),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _p.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _header(),
          Transform.translate(
            offset: const Offset(0, -40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _p.background, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _query,
                          onChanged: _kb.search,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(color: _p.text, fontSize: 14, fontFamily: _p.fontFamily),
                          decoration: InputDecoration(
                            hintText: 'Search for help',
                            hintStyle: TextStyle(color: _p.subtle),
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: _p.muted),
                            filled: true,
                            fillColor: _p.inputBackground,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        _products(),
                        const SizedBox(height: 14),
                        _articles(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _askCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
