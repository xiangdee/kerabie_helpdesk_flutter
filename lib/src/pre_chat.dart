import 'config.dart';
import 'controller.dart';
import 'models.dart';

/// The built-in name and email form, used when the organisation has not set its own questions.
const kerabieDefaultPreChatFields = [
  KerabieEnrichmentField(key: 'name', label: 'Your name', placeholder: 'Your name'),
  KerabieEnrichmentField(key: 'email', label: 'Email address', type: 'email', placeholder: 'Email address'),
];

/// The pre-chat questions and what is known about the visitor. The chat and a call ask the same form, so a visitor
/// cannot skip it by calling instead.
extension KerabiePreChat on KerabieController {
  /// The organisation's own questions when it set up a pre-chat form, otherwise the built-in name and email.
  List<KerabieEnrichmentField> get preChatFields {
    final custom = chat.customerEnrichmentEnabled == true ? chat.customerEnrichmentForm ?? const <KerabieEnrichmentField>[] : const <KerabieEnrichmentField>[];
    return custom.isNotEmpty ? custom : kerabieDefaultPreChatFields;
  }

  bool get hasAnsweredPreChat {
    final user = currentUser;
    return (user?.name?.isNotEmpty ?? false) || (user?.email?.isNotEmpty ?? false) || (user?.customAttributes.isNotEmpty ?? false);
  }

  /// The organisation asks for details before a chat, and this visitor has not given any yet.
  bool get needsPreChatDetails => chat.customerEnrichmentEnabled == true && !hasAnsweredPreChat;

  void submitPreChat(Map<String, String> answers) {
    // name, email and phone are the contact's own fields; every other answer is a custom attribute.
    var user = currentUser ?? const KerabieUser();
    final custom = {...user.customAttributes};
    for (final f in preChatFields) {
      final v = (answers[f.key] ?? '').trim();
      if (v.isEmpty) continue;
      switch (f.key) {
        case 'name':
          user = user.copyWith(name: v);
        case 'email':
          user = user.copyWith(email: v);
        case 'phone':
          user = user.copyWith(phone: v);
        default:
          custom[f.key] = v;
      }
    }
    setUser(user.copyWith(customAttributes: custom));
  }
}
