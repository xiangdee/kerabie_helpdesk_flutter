import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'controller.dart';

enum KerabieTicketPriority { low, normal, high, urgent }

/// `WAITING`, `ACTIVE`, `RESOLVED` or `CLOSED`.
@immutable
class KerabieTicket {
  const KerabieTicket({required this.id, this.subject, required this.status, required this.priority, this.slaDueAt, required this.createdAt});

  final int id;
  final String? subject;
  final String status;
  final KerabieTicketPriority priority;
  final DateTime? slaDueAt;
  final DateTime createdAt;

  bool get isClosed => status == 'CLOSED';

  static KerabieTicket? fromServer(Object? raw) {
    if (raw is! Map || raw['id'] is! num) return null;
    return KerabieTicket(
      id: (raw['id'] as num).toInt(),
      subject: raw['subject'] as String?,
      status: '${raw['status'] ?? 'WAITING'}',
      priority: switch ('${raw['priority']}'.toUpperCase()) {
        'LOW' => KerabieTicketPriority.low,
        'HIGH' => KerabieTicketPriority.high,
        'URGENT' => KerabieTicketPriority.urgent,
        _ => KerabieTicketPriority.normal,
      },
      slaDueAt: DateTime.tryParse('${raw['slaDueAt']}'),
      createdAt: DateTime.tryParse('${raw['createdAt']}') ?? DateTime.now(),
    );
  }
}

@immutable
class KerabieTicketMessage {
  const KerabieTicketMessage({required this.id, required this.body, required this.fromCustomer, this.senderName, required this.createdAt});

  final String id;
  final String body;
  final bool fromCustomer;
  final String? senderName;
  final DateTime createdAt;

  static KerabieTicketMessage? fromServer(Object? raw) {
    if (raw is! Map) return null;
    return KerabieTicketMessage(
      id: '${raw['id']}',
      body: '${raw['body'] ?? ''}',
      fromCustomer: raw['senderRole'] == 'customer',
      senderName: raw['senderName'] as String?,
      createdAt: DateTime.tryParse('${raw['createdAt']}') ?? DateTime.now(),
    );
  }
}

/// A ticket and its messages.
@immutable
class KerabieTicketThread {
  const KerabieTicketThread(this.ticket, this.messages);

  final KerabieTicket ticket;
  final List<KerabieTicketMessage> messages;
}

/// The visitor's tickets: list, open one, create, reply. Which tickets belong to this device rides on the session id
/// every request already carries.
class KerabieTickets extends ChangeNotifier {
  KerabieTickets(this._controller) {
    fetch();
  }

  final KerabieController _controller;

  List<KerabieTicket> _tickets = const [];
  // True until the first answer, so "No tickets yet." never flashes before the skeleton.
  bool _loading = true;
  bool _disposed = false;

  List<KerabieTicket> get tickets => _tickets;
  bool get loading => _loading;

  Future<void> fetch() async {
    _loading = true;
    _notify();
    try {
      final api = await _controller.waitForApi();
      final res = await api.get('/public/tickets');
      final raw = res['data'] is List ? res['data'] as List : const [];
      _tickets = raw.map(KerabieTicket.fromServer).whereType<KerabieTicket>().toList();
    } on KerabieException {
      // Keep the list we have.
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<KerabieTicketThread?> getTicket(int id) async {
    try {
      final api = await _controller.waitForApi();
      final res = await api.get('/public/tickets/$id');
      final ticket = KerabieTicket.fromServer(res['ticket']);
      if (ticket == null) return null;
      final raw = res['messages'] is List ? res['messages'] as List : const [];
      return KerabieTicketThread(ticket, raw.map(KerabieTicketMessage.fromServer).whereType<KerabieTicketMessage>().toList());
    } on KerabieException {
      return null;
    }
  }

  /// Returns the new ticket's id, or null when it could not be created.
  Future<int?> createTicket({
    required String subject,
    required String message,
    KerabieTicketPriority priority = KerabieTicketPriority.normal,
    String? name,
    String? email,
  }) async {
    try {
      final api = await _controller.waitForApi();
      final res = await api.post('/public/tickets', {
        'subject': subject,
        'message': message,
        'priority': priority.name.toUpperCase(),
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      });
      fetch();
      return (res['ticketId'] as num?)?.toInt();
    } on KerabieException {
      return null;
    }
  }

  Future<bool> reply(int id, String body) async {
    try {
      final api = await _controller.waitForApi();
      await api.post('/public/tickets/$id/reply', {'body': body});
      return true;
    } on KerabieException {
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
