import 'models.dart';

/// Who a user is, for telling one person from another: the app's own id, else the email. Empty for nobody.
String kerabiePersonOf(KerabieUser? user) {
  final id = user?.id;
  if (id != null && id.isNotEmpty) return 'id:$id';
  final email = user?.email;
  if (email != null && email.isNotEmpty) return 'email:${email.toLowerCase()}';
  return '';
}

/// Whether a session kept for [saved] is someone else's session for [current]. A session kept for nobody (an anonymous
/// visitor) is free to be taken by whoever signs in; one kept for a person is that person's only.
bool kerabieSessionIsOthers(String? saved, String current) => saved != null && saved.isNotEmpty && saved != current;
