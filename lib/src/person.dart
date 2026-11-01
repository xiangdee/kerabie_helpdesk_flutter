import 'models.dart';

/// Who a user is, for telling one person from another: the app's own id, else the email. Empty for nobody.
String kerabiePersonOf(KerabieUser? user) {
  final id = user?.id;
  if (id != null && id.isNotEmpty) return 'id:$id';
  final email = user?.email;
  if (email != null && email.isNotEmpty) return 'email:${email.toLowerCase()}';
  return '';
}
