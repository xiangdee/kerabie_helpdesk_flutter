import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../controller.dart';
import '../models.dart';
import 'dialog.dart';
import 'palette.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
const _danger = Color(0xFFDC2626);

/// Change name, download or email the transcript, and the privacy rows: download or erase everything held about the
/// visitor. The same rows the web widget's help screen has.
class KerabieSettingsScreen extends StatefulWidget {
  const KerabieSettingsScreen({super.key, required this.controller, required this.palette});

  final KerabieController controller;
  final KerabiePalette palette;

  @override
  State<KerabieSettingsScreen> createState() => _KerabieSettingsScreenState();
}

class _KerabieSettingsScreenState extends State<KerabieSettingsScreen> {
  // Short-lived status text under each row's title.
  final _notice = <String, String>{};

  KerabieController get _c => widget.controller;
  KerabiePalette get _p => widget.palette;

  void _flash(String key, String text) {
    if (!mounted) return;
    setState(() => _notice[key] = text);
    Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice.remove(key));
    });
  }

  Future<void> _changeName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        palette: _p,
        title: 'Change name',
        hint: 'This is the name our team sees in your conversations.',
        placeholder: 'Your name',
        initial: _c.currentUser?.name ?? '',
        confirmLabel: 'Save',
        maxLength: 80,
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _c.setUser((_c.currentUser ?? const KerabieUser()).copyWith(name: trimmed));
    _flash('name', '✓ Saved!');
  }

  Future<void> _downloadTranscript() async {
    final id = _c.conversationId;
    if (id == null) return _flash('download', 'No conversation to download yet');
    try {
      // A phone has no download folder to open, so the share sheet (save, copy, AirDrop) is the way out.
      final res = await _c.api!.get('/public/widget/conversations/$id/export');
      final transcript = res['transcript'];
      if (transcript is! String || transcript.isEmpty) throw KerabieException('empty');
      await SharePlus.instance.share(ShareParams(text: transcript, sharePositionOrigin: _shareOrigin()));
    } catch (_) {
      _flash('download', "Couldn't download — try again");
    }
  }

  Future<void> _emailTranscript() async {
    final id = _c.conversationId;
    if (id == null) return;
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _TextDialog(
        palette: _p,
        title: 'Email transcript',
        hint: "We'll send a copy of this conversation to:",
        placeholder: 'your@email.com',
        initial: _c.currentUser?.email ?? '',
        confirmLabel: 'Send',
        busyLabel: 'Sending…',
        keyboard: TextInputType.emailAddress,
        validate: (v) => _emailPattern.hasMatch(v) ? null : 'Enter a valid email address',
        submit: (email) async {
          try {
            await _c.api!.post('/public/widget/conversations/$id/export/email', {'email': email});
            return null;
          } catch (_) {
            return "Couldn't send the email — try again";
          }
        },
      ),
    );
    if (sent == true) _flash('email', '✓ Sent!');
  }

  Future<void> _downloadMyData() async {
    try {
      final data = await _c.api!.get('/public/widget/my-data');
      final conversations = data['conversations'];
      if (data['profile'] == null && (conversations is! List || conversations.isEmpty)) {
        return _flash('data', "We don't hold any data about you yet.");
      }
      await SharePlus.instance.share(ShareParams(text: const JsonEncoder.withIndent('  ').convert(data), sharePositionOrigin: _shareOrigin()));
    } catch (_) {
      _flash('data', "Couldn't download your data — try again");
    }
  }

  Future<void> _deleteMyData() async {
    var error = '';
    var busy = false;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => KerabieDialogShell(
          palette: _p,
          title: 'Delete my data',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("This permanently deletes your conversations and contact details from this chat. It can't be undone.", style: _hint(_p.text)),
              if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error, style: _hint(_danger))),
            ],
          ),
          actions: [
            KerabieDialogButton(label: 'Cancel', palette: _p, outlined: true, onPressed: busy ? null : () => Navigator.of(ctx).pop(false)),
            KerabieDialogButton(
              label: busy ? 'Deleting…' : 'Yes, delete',
              palette: _p,
              color: _danger,
              textColor: Colors.white,
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        await _c.api!.delete('/public/widget/my-data');
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } catch (_) {
                        setState(() {
                          busy = false;
                          error = "Couldn't delete your data — try again";
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    if (deleted == true) _flash('data', 'Your data has been deleted.');
  }

  /// On an iPad the share sheet must point at something on screen.
  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  }

  TextStyle _hint(Color color) => TextStyle(fontSize: 12.5, color: color, fontFamily: _p.fontFamily);

  Widget _row(String label, String hint, VoidCallback onTap, {Color? labelColor, String? key}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor ?? _p.text, fontFamily: _p.fontFamily)),
            const SizedBox(height: 2),
            Text(_notice[key ?? label] ?? hint, style: _hint(_p.muted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _p.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Change Name', _c.currentUser?.name ?? 'Set the name shown to our team', _changeName, key: 'name'),
          if (_c.conversationId != null) ...[
            _row('Download Transcript', 'Share a copy of your chat history', _downloadTranscript, key: 'download'),
            _row('Email Transcript', 'Send transcript to your email', _emailTranscript, key: 'email'),
          ],
          Divider(height: 16, thickness: 0.5, color: _p.border),
          _row('Download my data', 'Get a copy of the data we hold about you', _downloadMyData, key: 'data'),
          _row('Delete my data', 'Permanently erase your conversations and contact details', _deleteMyData, labelColor: _danger),
        ],
      ),
    );
  }
}

/// A dialog with one text box. Pops the text (or true after [submit] succeeds). It owns its controller, so the box is
/// not disposed while the dialog is still animating away.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.palette,
    required this.title,
    required this.hint,
    required this.placeholder,
    required this.initial,
    required this.confirmLabel,
    this.busyLabel,
    this.maxLength,
    this.keyboard,
    this.validate,
    this.submit,
  });

  final KerabiePalette palette;
  final String title;
  final String hint;
  final String placeholder;
  final String initial;
  final String confirmLabel;
  final String? busyLabel;
  final int? maxLength;
  final TextInputType? keyboard;

  /// Returns a problem to show, or null when the text is fine.
  final String? Function(String)? validate;

  /// Runs on confirm and returns a problem to show, or null when it worked. Without it the dialog pops the text.
  final Future<String?> Function(String)? submit;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _input = TextEditingController(text: widget.initial);
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final problem = widget.validate?.call(text);
    if (problem != null) return setState(() => _error = problem);
    final submit = widget.submit;
    if (submit == null) return Navigator.of(context).pop(text);
    setState(() {
      _busy = true;
      _error = '';
    });
    final failed = await submit(text);
    if (!mounted) return;
    if (failed == null) return Navigator.of(context).pop(true);
    setState(() {
      _busy = false;
      _error = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return KerabieDialogShell(
      palette: p,
      title: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.hint, style: TextStyle(fontSize: 12.5, color: p.muted, fontFamily: p.fontFamily)),
          const SizedBox(height: 8),
          TextField(
            controller: _input,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboard,
            onSubmitted: (_) => _confirm(),
            textCapitalization: widget.keyboard == TextInputType.emailAddress ? TextCapitalization.none : TextCapitalization.words,
            style: TextStyle(color: p.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: TextStyle(color: p.subtle),
              counterText: '',
              filled: true,
              fillColor: p.inputBackground,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border, width: 0.5)),
            ),
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error, style: const TextStyle(fontSize: 12.5, color: _danger))),
        ],
      ),
      actions: [
        KerabieDialogButton(label: 'Cancel', palette: p, outlined: true, onPressed: _busy ? null : () => Navigator.of(context).pop()),
        KerabieDialogButton(label: _busy ? (widget.busyLabel ?? widget.confirmLabel) : widget.confirmLabel, palette: p, onPressed: _busy ? null : _confirm),
      ],
    );
  }
}
