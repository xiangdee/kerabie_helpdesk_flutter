import 'package:flutter/material.dart';

import '../storage.dart';
import 'emoji_data.dart';
import 'palette.dart';

const _recentsKey = 'recent_emoji';
const _maxRecents = 24;

final _all = [for (final g in kerabieEmojiGroups) ...g.emoji];
final _byEmoji = {for (final x in _all) x.emoji: x};

/// The emoji panel above the composer: search, category tabs and the ones used last.
class KerabieEmojiPicker extends StatefulWidget {
  const KerabieEmojiPicker({super.key, required this.palette, required this.storage, required this.onSelect});

  final KerabiePalette palette;
  final KerabieStorage storage;
  final ValueChanged<String> onSelect;

  @override
  State<KerabieEmojiPicker> createState() => _KerabieEmojiPickerState();
}

class _KerabieEmojiPickerState extends State<KerabieEmojiPicker> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  List<String> _recents = [];
  final _viewportKey = GlobalKey();
  String _active = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.storage.read<List<dynamic>>(_recentsKey).then((r) {
      if (r != null && mounted) setState(() => _recents = r.whereType<String>().toList());
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<KerabieEmojiGroup> get _sections => [
        if (_recents.isNotEmpty)
          KerabieEmojiGroup('recent', 'Recently used', '🕘', [for (final e in _recents) _byEmoji[e] ?? KerabieEmoji(e, '')]),
        ...kerabieEmojiGroups,
      ];

  /// Every typed word must match the emoji's name or keywords ("red heart", "thumbs up").
  List<KerabieEmoji> get _results {
    final words = _query.text.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    return _all.where((x) => words.every(x.keywords.contains)).toList();
  }

  void _pick(String emoji) {
    final next = [emoji, ..._recents.where((x) => x != emoji)].take(_maxRecents).toList();
    setState(() => _recents = next);
    widget.storage.write(_recentsKey, next);
    widget.onSelect(emoji);
  }

  /// Highlights the tab of whichever section is at the top of the list.
  void _onScroll() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || _query.text.trim().isNotEmpty) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var current = _sections.first.id;
    for (final s in _sections) {
      final box = _sectionKeys[s.id]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.localToGlobal(Offset.zero).dy <= top + 8) current = s.id;
    }
    if (current != _active) setState(() => _active = current);
  }

  void _jumpTo(String id) {
    setState(() => _active = id);
    final context = _sectionKeys[id]?.currentContext;
    if (context != null) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 200), alignment: 0);
  }

  Widget _grid(List<KerabieEmoji> list) => Wrap(
        children: [
          for (final x in list)
            SizedBox(
              width: 32,
              height: 32,
              child: InkWell(
                onTap: () => _pick(x.emoji),
                child: Semantics(
                  label: x.keywords.split(' ').take(3).join(' '),
                  child: Center(child: Text(x.emoji, style: const TextStyle(fontSize: 20))),
                ),
              ),
            ),
        ],
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 2),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: widget.palette.subtle)),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final searching = _query.text.trim().isNotEmpty;
    final sections = _sections;
    final current = _active.isNotEmpty ? _active : sections.first.id;
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border, width: 0.5),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _query,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: p.text, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search emoji',
                  hintStyle: TextStyle(color: p.subtle),
                  filled: true,
                  fillColor: p.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border, width: 0.5)),
                ),
              ),
            ),
          ),
          if (!searching)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border, width: 0.5))),
              child: Row(
                children: [
                  for (final s in sections)
                    Expanded(
                      child: Semantics(
                        label: s.label,
                        selected: current == s.id,
                        child: InkWell(
                          onTap: () => _jumpTo(s.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(width: 2, color: current == s.id ? p.accent : Colors.transparent)),
                            ),
                            child: Opacity(
                              opacity: current == s.id ? 1 : 0.5,
                              child: Center(child: Text(s.icon, style: const TextStyle(fontSize: 15))),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(
            key: _viewportKey,
            height: 200,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: searching
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Results'),
                        if (_results.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text('No emoji found', style: TextStyle(fontSize: 13, color: p.subtle))),
                          )
                        else
                          _grid(_results),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in sections)
                          Column(
                            key: _sectionKeys.putIfAbsent(s.id, GlobalKey.new),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [_label(s.label), _grid(s.emoji)],
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
