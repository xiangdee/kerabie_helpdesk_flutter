import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/src/context_message.dart';
import 'package:kerabie_helpdesk_flutter/src/models.dart';

void main() {
  test('names what the help is about, its reference and its main details', () {
    final text = kerabieContextMessage(const KerabieChatContext(
      type: 'transaction',
      id: 'TX-1',
      title: '₦5,000 debit',
      data: {'reference': 'TX-1', 'narration': 'Order 55', 'payment_method': 'wallet', 'amount': '₦5,000'},
    ));

    expect(
      text,
      'I need help with ₦5,000 debit (ref TX-1).\nReference: TX-1\nNarration: Order 55\nPayment method: wallet\nAmount: ₦5,000',
    );
  });

  test('uses the type when there is no title, and skips the reference when the title already has it', () {
    expect(kerabieContextMessage(const KerabieChatContext(type: 'order', id: '9')), 'I need help with order (ref 9).');
    expect(kerabieContextMessage(const KerabieChatContext(type: 'order', id: '9', title: 'Order 9')), 'I need help with Order 9.');
  });

  test('keeps only simple values, and at most six detail lines', () {
    final lines = kerabieContextMessage(const KerabieChatContext(type: 'order', data: {
      'a': 1, 'b': true, 'c': 'x', 'd': {'nested': 1}, 'e': [1], 'f': '', 'g': 'g', 'h': 'h', 'i': 'i', 'j': 'j', 'k': 'k',
    })).split('\n');

    expect(lines.length, 7);
    expect(lines.sublist(1, 4), ['A: 1', 'B: true', 'C: x']);
    expect(lines.any((l) => l.startsWith('D:') || l.startsWith('E:') || l.startsWith('F:')), isFalse);
  });

  test('shortens a very long value and the whole message', () {
    final text = kerabieContextMessage(KerabieChatContext(type: 'order', data: {'note': 'y' * 500}));

    expect(text.split('\n')[1].length, lessThanOrEqualTo('Note: '.length + 120));
    expect(kerabieContextMessage(KerabieChatContext(type: 'order', message: 'z' * 2000)).length, lessThanOrEqualTo(600));
  });

  test('an app can give its own wording', () {
    expect(kerabieContextMessage(const KerabieChatContext(type: 'order', id: '9', message: '  Where is my order?  ')), 'Where is my order?');
  });
}
