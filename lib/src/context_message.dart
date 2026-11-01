import 'models.dart';

const _maxLines = 6;
const _maxValue = 120;
const _maxTotal = 600;

String _label(String key) {
  final spaced = key.replaceAll(RegExp(r'[_-]+'), ' ').replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return spaced.isEmpty ? spaced : spaced[0].toUpperCase() + spaced.substring(1);
}

String _cut(String text, int max) => text.length <= max ? text : text.substring(0, max);

/// The message a "get help with this" tap puts in the message box: what it is about and its main details, so the
/// customer only has to add what went wrong. An app can give its own wording with [KerabieChatContext.message].
String kerabieContextMessage(KerabieChatContext context) {
  final own = context.message?.trim();
  if (own != null && own.isNotEmpty) return _cut(own, _maxTotal);
  final title = context.title?.trim();
  final what = (title != null && title.isNotEmpty) ? title : context.type;
  final id = context.id;
  final ref = (id != null && id.isNotEmpty && !what.contains(id)) ? ' (ref $id)' : '';
  final lines = <String>['I need help with $what$ref.'];
  for (final entry in (context.data ?? const <String, dynamic>{}).entries) {
    if (lines.length > _maxLines) break;
    final value = entry.value;
    if (value is! String && value is! num && value is! bool) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) lines.add('${_label(entry.key)}: ${_cut(text, _maxValue)}');
  }
  return _cut(lines.join('\n'), _maxTotal);
}
