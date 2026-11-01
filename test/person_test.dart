import 'package:flutter_test/flutter_test.dart';
import 'package:kerabie_helpdesk_flutter/src/models.dart';
import 'package:kerabie_helpdesk_flutter/src/person.dart';

void main() {
  test('the app id tells people apart, whatever else changes', () {
    expect(kerabiePersonOf(const KerabieUser(id: '42', email: 'a@b.co')), kerabiePersonOf(const KerabieUser(id: '42', email: 'other@b.co')));
    expect(kerabiePersonOf(const KerabieUser(id: '42')), isNot(kerabiePersonOf(const KerabieUser(id: '43'))));
  });

  test('without an id the email decides, ignoring case', () {
    expect(kerabiePersonOf(const KerabieUser(email: 'Terry@Mail.com')), kerabiePersonOf(const KerabieUser(email: 'terry@mail.com')));
    expect(kerabiePersonOf(const KerabieUser(email: 'a@b.co')), isNot(kerabiePersonOf(const KerabieUser(email: 'c@d.co'))));
  });

  test('an id and an email are never taken for each other', () {
    expect(kerabiePersonOf(const KerabieUser(id: 'a@b.co')), isNot(kerabiePersonOf(const KerabieUser(email: 'a@b.co'))));
  });

  test('nobody, or someone with no id and no email, is the empty person', () {
    expect(kerabiePersonOf(null), '');
    expect(kerabiePersonOf(const KerabieUser()), '');
  });
}
