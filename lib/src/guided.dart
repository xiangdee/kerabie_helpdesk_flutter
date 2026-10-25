import 'package:flutter/foundation.dart';

import 'models.dart';

/// One button of a guided flow: a menu the organisation built in the dashboard ("What would you like help with?").
@immutable
class KerabieGuidedChoice {
  const KerabieGuidedChoice({required this.id, required this.label});

  final String id;
  final String label;

  static KerabieGuidedChoice? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    return id is String && label is String ? KerabieGuidedChoice(id: id, label: label) : null;
  }

  @override
  bool operator ==(Object other) => other is KerabieGuidedChoice && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// The opening question of the organisation's guided flow with its buttons, shown before the visitor has typed anything.
@immutable
class KerabieGuidedGreeting {
  const KerabieGuidedGreeting({required this.flowId, required this.message, required this.choices});

  final String flowId;
  final String message;
  final List<KerabieGuidedChoice> choices;

  static KerabieGuidedGreeting? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final flowId = raw['flowId'];
    final message = raw['message'];
    final choices = raw['choices'];
    if (flowId is! String || message is! String || choices is! List) return null;
    final parsed = choices.map(KerabieGuidedChoice.fromServer).whereType<KerabieGuidedChoice>().toList();
    return parsed.isEmpty ? null : KerabieGuidedGreeting(flowId: flowId, message: message, choices: parsed);
  }
}

/// A tap on a guided flow's button, sent with the message whose text is the button's label.
typedef KerabieChoice = ({String flowId, String choiceId});

/// Which guided-flow buttons are on screen: the greeting's while nothing has been sent, otherwise those on the latest
/// bot message, until the visitor answers it (any later message from them removes them). Same rule as the web widget
/// (kerabie-chat-widget/src/utils/guidedChoices.ts) and the React Native SDK.
({String flowId, List<KerabieGuidedChoice> choices})? kerabieActiveChoices(
  List<KerabieMessage> messages,
  KerabieGuidedGreeting? greeting, {
  bool greetingAllowed = true,
}) {
  if (messages.isEmpty) {
    return greeting != null && greetingAllowed && greeting.choices.isNotEmpty ? (flowId: greeting.flowId, choices: greeting.choices) : null;
  }
  final last = messages.last;
  if (last.isFromVisitor) return null;
  final choices = last.metadata['choices'];
  final flowId = last.metadata['flowId'];
  if (choices is! List || flowId is! String) return null;
  final valid = choices.map(KerabieGuidedChoice.fromServer).whereType<KerabieGuidedChoice>().toList();
  return valid.isEmpty ? null : (flowId: flowId, choices: valid);
}
