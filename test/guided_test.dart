// ignore_for_file: prefer_const_literals_to_create_immutables
import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';

KerabieMessage _bot(Map<String, dynamic> metadata) => KerabieMessage(
      id: '1',
      body: 'Pick one',
      createdAt: DateTime(2026),
      sender: KerabieSender.bot,
      metadata: metadata,
    );

KerabieMessage _visitor() => KerabieMessage(id: '2', body: 'Pricing', createdAt: DateTime(2026), sender: KerabieSender.visitor);

const _greeting = KerabieGuidedGreeting(
  flowId: 'f1',
  message: 'What would you like help with?',
  choices: [KerabieGuidedChoice(id: 'a', label: 'Pricing'), KerabieGuidedChoice(id: 'b', label: 'Sales')],
);

void main() {
  group('kerabieActiveChoices', () {
    test('shows the greeting buttons while nothing has been sent', () {
      final active = kerabieActiveChoices(const [], _greeting);
      expect(active?.flowId, 'f1');
      expect(active?.choices.map((c) => c.label), ['Pricing', 'Sales']);
    });

    test('shows nothing without a greeting, or while the pre-chat form must come first', () {
      expect(kerabieActiveChoices(const [], null), isNull);
      expect(kerabieActiveChoices(const [], _greeting, greetingAllowed: false), isNull);
    });

    test('shows the buttons on the latest bot message', () {
      final active = kerabieActiveChoices([
        _visitor(),
        _bot({'flowId': 'f1', 'choices': [{'id': 'x', 'label': 'Yes'}]}),
      ], _greeting);
      expect(active?.choices.single.label, 'Yes');
    });

    test('removes them as soon as the visitor has answered', () {
      final messages = [_bot({'flowId': 'f1', 'choices': [{'id': 'x', 'label': 'Yes'}]}), _visitor()];
      expect(kerabieActiveChoices(messages, _greeting), isNull);
    });

    test('only the LAST message counts, not an older bot message that had buttons', () {
      final messages = [_bot({'flowId': 'f1', 'choices': [{'id': 'x', 'label': 'Yes'}]}), _bot({})];
      expect(kerabieActiveChoices(messages, _greeting), isNull);
    });

    test('ignores malformed metadata instead of breaking the chat', () {
      expect(kerabieActiveChoices([_bot({'flowId': 'f1', 'choices': 'nope'})], _greeting), isNull);
      expect(kerabieActiveChoices([_bot({'choices': [{'id': 'x', 'label': 'Yes'}]})], _greeting), isNull);
      final partial = kerabieActiveChoices([
        _bot({'flowId': 'f1', 'choices': [{'id': 1}, null, {'id': 'ok', 'label': 'Fine'}]}),
      ], _greeting);
      expect(partial?.choices.single.label, 'Fine');
    });
  });

  group('the greeting from the server', () {
    test('is read from the widget settings', () {
      final settings = KerabieSettings.fromServer({
        'guidedGreeting': {
          'flowId': 'f1',
          'message': 'Hi',
          'choices': [{'id': 'a', 'label': 'Pricing'}],
        },
      });
      expect(settings.chat.guidedGreeting?.message, 'Hi');
      expect(settings.chat.guidedGreeting?.choices.single.id, 'a');
    });

    test('is absent when the organisation has no flow, or the data is malformed', () {
      expect(KerabieSettings.fromServer({'guidedGreeting': null}).chat.guidedGreeting, isNull);
      expect(KerabieSettings.fromServer(const {}).chat.guidedGreeting, isNull);
      expect(KerabieSettings.fromServer({'guidedGreeting': {'flowId': 'f1', 'message': 'Hi', 'choices': []}}).chat.guidedGreeting, isNull);
    });
  });

  test('a guided flow message counts as the bot, like an AI reply', () {
    final message = KerabieMessage.fromServer({
      'id': 5,
      'body': 'Plans start free.',
      'senderRole': 'agent',
      'createdAt': '2026-10-25T10:00:00Z',
      'metadata': {'source': 'guided', 'flowId': 'f1'},
    });
    expect(message.sender, KerabieSender.bot);
  });
}
