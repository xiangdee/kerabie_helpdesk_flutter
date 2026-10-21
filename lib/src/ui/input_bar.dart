import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import 'emoji_picker.dart';
import 'palette.dart';

/// The composer: attach button, text field with an emoji button, send button, and the picked file above them.
class KerabieInputBar extends StatefulWidget {
  const KerabieInputBar({
    super.key,
    required this.controller,
    required this.palette,
    required this.storage,
    required this.onChanged,
    required this.onSend,
    this.onAttach,
    this.pending,
    this.isUploading = false,
    this.onRemoveAttachment,
    this.disabled = false,
    this.placeholder,
  });

  final TextEditingController controller;
  final KerabiePalette palette;
  final KerabieStorage storage;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Null hides the attach button.
  final VoidCallback? onAttach;
  final KerabiePickedFile? pending;
  final bool isUploading;
  final VoidCallback? onRemoveAttachment;
  final bool disabled;
  final String? placeholder;

  @override
  State<KerabieInputBar> createState() => _KerabieInputBarState();
}

class _KerabieInputBarState extends State<KerabieInputBar> {
  bool _showEmoji = false;

  bool get _canSend =>
      (widget.controller.text.trim().isNotEmpty || widget.pending != null) && !widget.disabled && !widget.isUploading;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(KerabieInputBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _send() {
    if (!_canSend) return;
    widget.onSend();
    setState(() => _showEmoji = false);
  }

  void _insertEmoji(String emoji) {
    final c = widget.controller;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    final text = c.text.replaceRange(at, end, emoji);
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at + emoji.length));
    widget.onChanged(text);
  }

  Widget _pendingRow(KerabiePalette p) {
    final file = widget.pending!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: file.isImage
                ? Image(image: ResizeImage(FileImage(File(file.path)), width: 96), width: 32, height: 32, fit: BoxFit.cover)
                : Container(width: 32, height: 32, color: p.surfaceStrong, alignment: Alignment.center, child: const Text('📎', style: TextStyle(fontSize: 15))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text))),
          if (widget.isUploading)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            InkWell(onTap: widget.onRemoveAttachment, child: Icon(Icons.close_rounded, size: 16, color: p.subtle)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final attachDisabled = widget.disabled || widget.pending != null;
    final canSend = _canSend;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: p.background, border: Border(top: BorderSide(color: p.border, width: 0.5))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.pending != null) _pendingRow(p),
            if (_showEmoji)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: KerabieEmojiPicker(palette: p, storage: widget.storage, onSelect: _insertEmoji),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.onAttach != null)
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: attachDisabled ? null : widget.onAttach,
                    icon: Icon(Icons.attach_file_rounded, size: 20, color: attachDisabled ? p.subtle : p.muted),
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    enabled: !widget.disabled,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: widget.onChanged,
                    style: TextStyle(color: p.text, fontSize: 15, fontFamily: p.fontFamily),
                    decoration: InputDecoration(
                      hintText: widget.placeholder ?? 'Type a message…',
                      hintStyle: TextStyle(color: p.subtle),
                      filled: true,
                      fillColor: p.inputBackground,
                      contentPadding: const EdgeInsets.fromLTRB(16, 10, 40, 10),
                      suffixIcon: IconButton(
                        tooltip: 'Emoji',
                        onPressed: widget.disabled ? null : () => setState(() => _showEmoji = !_showEmoji),
                        icon: const Text('🙂', style: TextStyle(fontSize: 17)),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(p.radius + 4), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: canSend ? null : p.surfaceStrong,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      width: 40,
                      height: 40,
                      decoration: canSend ? ShapeDecoration(shape: const CircleBorder(), color: p.gradient ? null : p.primary, gradient: p.brandGradient) : null,
                      child: InkWell(
                        onTap: canSend ? _send : null,
                        child: Icon(Icons.arrow_upward_rounded, size: 20, color: canSend ? p.onPrimary : p.subtle),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
