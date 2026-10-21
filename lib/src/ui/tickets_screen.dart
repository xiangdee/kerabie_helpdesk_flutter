import 'package:flutter/material.dart';

import '../provider.dart';
import '../tickets.dart';
import 'palette.dart';
import 'screen_header.dart';
import 'skeleton.dart';

const _priorityColors = {
  KerabieTicketPriority.low: Color(0xFF94A3B8),
  KerabieTicketPriority.normal: Color(0xFF6366F1),
  KerabieTicketPriority.high: Color(0xFFF59E0B),
  KerabieTicketPriority.urgent: Color(0xFFEF4444),
};

/// Status pill colours follow the web widget: in progress amber, resolved green, anything else blue.
({String label, Color bg, Color fg}) kerabieTicketStatusStyle(String status) {
  final key = status.toUpperCase();
  if (key == 'RESOLVED' || key == 'CLOSED') {
    return (label: key == 'CLOSED' ? 'Closed' : 'Resolved', bg: const Color(0xFFDFF5EA), fg: const Color(0xFF17694A));
  }
  if (key == 'PENDING' || key == 'IN_PROGRESS') {
    return (label: 'In progress', bg: const Color(0xFFFFF3D6), fg: const Color(0xFF8A5A00));
  }
  return (label: 'Open', bg: const Color(0xFFE3EDFF), fg: const Color(0xFF1D4ED8));
}

String kerabieAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final mins = ((now ?? DateTime.now()).difference(time).inSeconds / 60).round().clamp(0, 1 << 30);
  if (mins < 1) return 'just now';
  if (mins < 60) return '${mins}m ago';
  if (mins < 1440) return '${(mins / 60).round()}h ago';
  return '${(mins / 1440).round()}d ago';
}

String _priorityLabel(KerabieTicketPriority p) => p.name[0].toUpperCase() + p.name.substring(1);

/// The visitor's tickets, a form to open a new one, and each ticket's conversation.
class KerabieTicketsScreen extends StatefulWidget {
  const KerabieTicketsScreen({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<KerabieTicketsScreen> createState() => _KerabieTicketsScreenState();
}

class _KerabieTicketsScreenState extends State<KerabieTicketsScreen> {
  KerabieTickets? _tickets;
  bool _creating = false;
  int? _selectedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickets ??= KerabieTickets(KerabieProvider.of(context, listen: false));
  }

  @override
  void dispose() {
    _tickets?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final palette = KerabiePalette.of(context, controller);
    final tickets = _tickets!;

    if (_selectedId != null) {
      return KerabieTicketDetailScreen(
        tickets: tickets,
        ticketId: _selectedId!,
        onClose: () {
          setState(() => _selectedId = null);
          tickets.fetch();
        },
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            KerabieScreenHeader(
              title: _creating ? 'New ticket' : 'Tickets',
              palette: palette,
              closeLabel: _creating ? 'Back' : 'Close',
              onClose: _creating ? () => setState(() => _creating = false) : widget.onClose,
            ),
            Expanded(
              child: _creating
                  ? _NewTicketForm(
                      tickets: tickets,
                      palette: palette,
                      onCancel: () => setState(() => _creating = false),
                      onCreated: (id) => setState(() {
                        _creating = false;
                        _selectedId = id;
                      }),
                    )
                  : _list(tickets, palette),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(KerabieTickets tickets, KerabiePalette palette) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your tickets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.text)),
              Material(
                color: palette.primary,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _creating = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text('+ New ticket', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: palette.onPrimary)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: tickets,
            builder: (_, __) {
              if (tickets.loading) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (var i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(widthFactor: i.isEven ? 0.75 : 0.55, child: KerabieSkeleton(color: palette.surfaceStrong, height: 14)),
                              const SizedBox(height: 8),
                              Row(children: [
                                KerabieSkeleton(color: palette.surfaceStrong, width: 54, height: 16, borderRadius: 999),
                                const SizedBox(width: 8),
                                KerabieSkeleton(color: palette.surfaceStrong, width: 70, height: 16, borderRadius: 999),
                              ]),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }
              if (tickets.tickets.isEmpty) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(padding: const EdgeInsets.only(top: 32), child: Text('No tickets yet.', style: TextStyle(fontSize: 13, color: palette.subtle))),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                itemCount: tickets.tickets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final t = tickets.tickets[i];
                  final status = kerabieTicketStatusStyle(t.status);
                  return Material(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedId = t.id),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(t.subject ?? 'Ticket #${t.id}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.text)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(color: status.bg, borderRadius: BorderRadius.circular(999)),
                                  child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status.fg)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('#${t.id} · ${_priorityLabel(t.priority)} priority · ${kerabieAgo(t.createdAt)}',
                                style: TextStyle(fontSize: 12.5, color: palette.muted)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewTicketForm extends StatefulWidget {
  const _NewTicketForm({required this.tickets, required this.palette, required this.onCancel, required this.onCreated});

  final KerabieTickets tickets;
  final KerabiePalette palette;
  final VoidCallback onCancel;
  final ValueChanged<int> onCreated;

  @override
  State<_NewTicketForm> createState() => _NewTicketFormState();
}

class _NewTicketFormState extends State<_NewTicketForm> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _email = TextEditingController();
  KerabieTicketPriority _priority = KerabieTicketPriority.normal;
  bool _submitting = false;
  bool _failed = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _message.text.trim();
    if (message.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _failed = false;
    });
    final id = await widget.tickets.createTicket(
      subject: _subject.text.trim().isEmpty ? 'New ticket' : _subject.text.trim(),
      message: message,
      priority: _priority,
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _failed = id == null;
    });
    if (id != null) widget.onCreated(id);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: widget.palette.text)),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: widget.palette.subtle),
        filled: true,
        fillColor: widget.palette.inputBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: widget.palette.border)),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final style = TextStyle(color: p.text, fontSize: 14);
    final canSubmit = _message.text.trim().isNotEmpty && !_submitting;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Subject'),
          TextField(controller: _subject, style: style, decoration: _decoration('What do you need help with?')),
          _label('Message'),
          TextField(controller: _message, style: style, minLines: 4, maxLines: 6, onChanged: (_) => setState(() {}), decoration: _decoration('Describe your issue…')),
          _label('Email (optional — get updates by email)'),
          TextField(controller: _email, style: style, keyboardType: TextInputType.emailAddress, textCapitalization: TextCapitalization.none, decoration: _decoration('you@example.com')),
          _label('Priority'),
          Wrap(
            spacing: 8,
            children: [
              for (final priority in KerabieTicketPriority.values)
                GestureDetector(
                  onTap: () => setState(() => _priority = priority),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _priority == priority ? _priorityColors[priority] : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _priorityColors[priority]!, width: 1.5),
                    ),
                    child: Text(priority.name.toUpperCase(),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _priority == priority ? Colors.white : _priorityColors[priority])),
                  ),
                ),
            ],
          ),
          if (_failed)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text("Couldn't create the ticket — try again", style: TextStyle(fontSize: 12.5, color: Color(0xFFDC2626)))),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
                  child: Text('Cancel', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Opacity(
                  opacity: _message.text.trim().isEmpty ? 0.5 : 1,
                  child: Material(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: canSubmit ? _submit : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _submitting
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary))
                              : Text('Submit ticket', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.onPrimary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One ticket: its conversation and a box to reply. A closed ticket cannot be replied to.
class KerabieTicketDetailScreen extends StatefulWidget {
  const KerabieTicketDetailScreen({super.key, required this.tickets, required this.ticketId, this.onClose});

  final KerabieTickets tickets;
  final int ticketId;
  final VoidCallback? onClose;

  @override
  State<KerabieTicketDetailScreen> createState() => _KerabieTicketDetailScreenState();
}

class _KerabieTicketDetailScreenState extends State<KerabieTicketDetailScreen> {
  KerabieTicketThread? _thread;
  bool _loading = true;
  bool _sending = false;
  final _draft = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final thread = await widget.tickets.getTicket(widget.ticketId);
    if (!mounted) return;
    setState(() {
      if (thread != null) _thread = thread;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final body = _draft.text.trim();
    if (body.isEmpty || _sending) return;
    _draft.clear();
    setState(() => _sending = true);
    final ok = await widget.tickets.reply(widget.ticketId, body);
    if (ok) await _load();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = KerabieProvider.of(context);
    final p = KerabiePalette.of(context, controller);
    final ticket = _thread?.ticket;
    final closed = ticket?.isClosed ?? false;
    final priorityColor = ticket == null ? p.primary : _priorityColors[ticket.priority]!;
    final messages = _thread?.messages ?? const [];

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  InkWell(
                    onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('‹ Back', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.accent)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ticket?.subject ?? 'Ticket #${widget.ticketId}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.text)),
                        if (ticket != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                  child: Text(ticket.priority.name.toUpperCase(),
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: priorityColor)),
                                ),
                                const SizedBox(width: 8),
                                Text(ticket.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.subtle)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      children: [
                        for (var i = 0; i < 4; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Align(
                              alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
                              child: FractionallySizedBox(
                                widthFactor: i % 3 == 0 ? 0.65 : 0.45,
                                child: KerabieSkeleton(color: p.surfaceStrong, height: 38, borderRadius: 16),
                              ),
                            ),
                          ),
                      ],
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[messages.length - 1 - i];
                        final agent = !m.fromCustomer;
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Align(
                            alignment: agent ? Alignment.centerLeft : Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                                decoration: BoxDecoration(
                                  color: agent ? p.agentBubble : p.primary,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(agent ? 4 : 16),
                                    topRight: Radius.circular(agent ? 16 : 4),
                                    bottomLeft: const Radius.circular(16),
                                    bottomRight: const Radius.circular(16),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (agent && m.senderName != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text(m.senderName!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.muted)),
                                      ),
                                    Text(m.body, style: TextStyle(fontSize: 14, color: agent ? p.text : p.onPrimary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      enabled: !closed,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: p.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Write a reply…',
                        hintStyle: TextStyle(color: p.subtle),
                        filled: true,
                        fillColor: p.inputBackground,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _draft.text.trim().isEmpty ? 0.5 : 1,
                    child: Material(
                      color: p.primary,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _sending || _draft.text.trim().isEmpty || closed ? null : _send,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text('Send', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.onPrimary)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
