import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import 'palette.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The pre-chat form: the organisation's own questions (dashboard: Messages, Pre-chat form), or the built-in name and
/// email form. Required and optional fields, email and number checks, multiple choice as tappable options.
class KerabiePreChatForm extends StatefulWidget {
  const KerabiePreChatForm({
    super.key,
    required this.fields,
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    required this.requireContact,
    required this.initial,
    required this.palette,
    required this.onSubmit,
  });

  final List<KerabieEnrichmentField> fields;
  final String title;
  final String subtitle;
  final String submitLabel;

  /// The built-in name and email form still needs at least one way to follow up.
  final bool requireContact;
  final Map<String, String> initial;
  final KerabiePalette palette;
  final ValueChanged<Map<String, String>> onSubmit;

  @override
  State<KerabiePreChatForm> createState() => _KerabiePreChatFormState();
}

class _KerabiePreChatFormState extends State<KerabiePreChatForm> {
  late final Map<String, String> _answers = Map.of(widget.initial);
  final _controllers = <String, TextEditingController>{};
  String _error = '';

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _validate() {
    for (final f in widget.fields) {
      final v = (_answers[f.key] ?? '').trim();
      if (f.required && v.isEmpty) return '${f.label} is required';
      if (v.isNotEmpty && f.type == 'email' && !_emailPattern.hasMatch(v)) return 'Enter a valid email address';
      if (v.isNotEmpty && f.type == 'number' && double.tryParse(v) == null) return '${f.label} must be a number';
    }
    if (widget.requireContact && (_answers['name'] ?? '').trim().isEmpty && (_answers['email'] ?? '').trim().isEmpty) {
      return 'Enter a name or email so we can follow up';
    }
    return '';
  }

  void _submit() {
    final problem = _validate();
    setState(() => _error = problem);
    if (problem.isEmpty) widget.onSubmit(Map.of(_answers));
  }

  Widget _field(KerabieEnrichmentField f) {
    final p = widget.palette;
    if (f.type == 'select') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in f.options)
            ChoiceChip(
              label: Text(o, style: TextStyle(fontSize: 13, color: _answers[f.key] == o ? p.onPrimary : p.text)),
              selected: _answers[f.key] == o,
              selectedColor: p.primary,
              backgroundColor: Colors.transparent,
              showCheckmark: false,
              side: BorderSide(color: _answers[f.key] == o ? p.primary : p.border),
              onSelected: (_) => setState(() => _answers[f.key] = o),
            ),
        ],
      );
    }
    final controller = _controllers.putIfAbsent(f.key, () => TextEditingController(text: _answers[f.key] ?? ''));
    return TextField(
      controller: controller,
      onChanged: (v) => _answers[f.key] = v,
      minLines: f.type == 'textarea' ? 3 : 1,
      maxLines: f.type == 'textarea' ? 5 : 1,
      keyboardType: switch (f.type) {
        'email' => TextInputType.emailAddress,
        'phone' => TextInputType.phone,
        'number' => const TextInputType.numberWithOptions(decimal: true, signed: true),
        'textarea' => TextInputType.multiline,
        _ => TextInputType.text,
      },
      inputFormatters: f.type == 'number' ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))] : null,
      textCapitalization: f.type == 'email' ? TextCapitalization.none : TextCapitalization.sentences,
      style: TextStyle(color: p.text, fontSize: 14, fontFamily: p.fontFamily),
      decoration: InputDecoration(
        hintText: f.placeholder,
        hintStyle: TextStyle(color: p.subtle),
        filled: true,
        fillColor: p.inputBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border, width: 0.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.background, border: Border(top: BorderSide(color: p.border, width: 0.5))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text, fontFamily: p.fontFamily)),
          const SizedBox(height: 2),
          Text(widget.subtitle, style: TextStyle(fontSize: 13, color: p.muted, fontFamily: p.fontFamily)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${f.label}${f.required ? '' : ' (optional)'}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.muted)),
                          const SizedBox(height: 4),
                          _field(f),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_error, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
            ),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: p.primary,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Center(
                    child: Text(widget.submitLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.onPrimary)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
