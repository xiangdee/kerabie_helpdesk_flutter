import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'controller.dart';

const _day = Duration(hours: 24);

/// A proactive message made in the dashboard (Campaigns).
@immutable
class KerabieCampaign {
  const KerabieCampaign({
    required this.id,
    required this.name,
    required this.message,
    this.imageUrl,
    this.ctaLabel,
    this.ctaAction = 'open_chat',
    this.ctaUrl,
    this.trigger = 'page_load',
    this.triggerValue,
    this.pages,
    this.audience = 'all',
    this.frequency = 'once_per_visitor',
  });

  final int id;
  final String name;
  final String message;

  /// A cover shown full width on top of the popup.
  final String? imageUrl;

  /// The button's label. No button when empty.
  final String? ctaLabel;

  /// `open_chat`, `open_kb` or `open_link`.
  final String ctaAction;
  final String? ctaUrl;

  /// `page_load`, `time_on_page`, `scroll_depth` or `exit_intent`. The last two only exist on websites; the app skips them.
  final String trigger;

  /// Seconds in the app, for `time_on_page`.
  final String? triggerValue;

  /// Comma separated screen patterns with `*` wildcards. Empty means every screen.
  final String? pages;

  /// `all`, `new`, `returning`, `not_chatted` or `country` (the server already decided the country from the IP).
  final String audience;

  /// `once_per_visitor`, `once_per_day` or `every_session`.
  final String frequency;

  static KerabieCampaign? fromServer(Object? raw) {
    if (raw is! Map || raw['id'] is! num) return null;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return KerabieCampaign(
      id: (raw['id'] as num).toInt(),
      name: '${raw['name'] ?? ''}',
      message: '${raw['message'] ?? ''}',
      imageUrl: text(raw['imageUrl']),
      ctaLabel: text(raw['ctaLabel']),
      ctaAction: text(raw['ctaAction']) ?? 'open_chat',
      ctaUrl: text(raw['ctaUrl']),
      trigger: text(raw['trigger']) ?? 'page_load',
      triggerValue: raw['triggerValue']?.toString(),
      pages: text(raw['pages']),
      audience: text(raw['audience']) ?? 'all',
      frequency: text(raw['frequency']) ?? 'once_per_visitor',
    );
  }
}

/// Triggers that make sense inside an app.
const _nativeTriggers = ['page_load', 'time_on_page'];

String _normalizePath(String s) {
  final withSlash = s.startsWith('/') ? s : '/$s';
  return (withSlash.length > 1 ? withSlash.replaceAll(RegExp(r'/+$'), '') : withSlash).toLowerCase();
}

/// Glob style match (`*` is anything) of the current screen path against a campaign's patterns.
bool kerabieMatchesScreen(String? pages, String? screen) {
  final patterns = (pages ?? '').split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (patterns.isEmpty) return true;
  // The app did not say where the user is, so a campaign for certain screens cannot be placed.
  if (screen == null) return false;
  final path = _normalizePath(screen.split('?').first);
  return patterns.any((p) {
    final escaped = RegExp.escape(_normalizePath(p)).replaceAll(r'\*', '.*');
    return RegExp('^$escaped\$', caseSensitive: false).hasMatch(path);
  });
}

/// What the rules need to know about the visitor and the moment.
@immutable
class KerabieEligibility {
  const KerabieEligibility({this.screen, required this.now, required this.returning, required this.hasChatted, this.lastShownAt, required this.shownThisLaunch});

  final String? screen;
  final DateTime now;

  /// The user had opened the app before this launch.
  final bool returning;
  final bool hasChatted;
  final DateTime? lastShownAt;

  /// Already shown since this app launch.
  final bool shownThisLaunch;
}

bool kerabieIsEligible(KerabieCampaign c, KerabieEligibility ctx) {
  if (!_nativeTriggers.contains(c.trigger)) return false;
  if (!kerabieMatchesScreen(c.pages, ctx.screen)) return false;

  if (c.audience == 'new' && ctx.returning) return false;
  if (c.audience == 'returning' && !ctx.returning) return false;
  if (c.audience == 'not_chatted' && ctx.hasChatted) return false;

  switch (c.frequency) {
    case 'once_per_visitor':
      return ctx.lastShownAt == null;
    case 'once_per_day':
      return ctx.lastShownAt == null || ctx.now.difference(ctx.lastShownAt!) >= _day;
    default:
      return !ctx.shownThisLaunch;
  }
}

/// Proactive campaigns inside the app. Queues each live campaign when its trigger fires, either a screen appearing
/// (`page_load`) or N seconds in the app (`time_on_page`), and reports what the visitor does with it. Nothing pops up
/// while the chat itself is open.
class KerabieCampaigns extends ChangeNotifier {
  KerabieCampaigns(
    this.controller, {
    this.pageLoadDelay = const Duration(milliseconds: 1500),
    this.autoHide = const Duration(seconds: 12),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    controller.addListener(_onController);
    controller.onVisitorMessage = noteReply;
    _load();
  }

  final KerabieController controller;

  /// Lets the chat history load so "has not chatted yet" is accurate.
  final Duration pageLoadDelay;
  final Duration autoHide;
  final DateTime Function() _now;

  static const _seenKey = 'campaign_seen';
  static const _visitedKey = 'has_visited';

  List<KerabieCampaign> _campaigns = const [];
  Map<String, int> _seen = {};
  bool _returning = false;
  bool _ready = false;
  bool _disposed = false;
  final _queued = <int>{}; // once per app launch
  final _reported = <int>{};
  final _queue = <KerabieCampaign>[];
  final _timers = <Timer>[];
  Timer? _pageLoadTimer;
  Timer? _hideTimer;
  int? _showingId;
  int? _engagedId;
  String? _lastScreen;
  bool _lastOpen = false;
  final DateTime _startedAt = DateTime.now();

  /// The campaign on screen, or null.
  KerabieCampaign? get current {
    if (_queue.isEmpty || controller.isOpen) return null;
    return _queue.first;
  }

  Future<void> _load() async {
    final api = await controller.waitForApi();
    final list = await _fetch(api);
    final seen = await controller.storage.readForever<Map<String, dynamic>>(_seenKey) ?? {};
    final before = await controller.storage.readForever<Object>(_visitedKey);
    if (before == null) await controller.storage.writeForever(_visitedKey, 1);
    if (_disposed) return;
    _campaigns = list;
    _seen = {for (final e in seen.entries) e.key: (e.value as num).toInt()};
    _returning = before != null;
    _ready = true;
    _lastScreen = controller.screen;

    // Time in app: one timer per campaign, measured from when the provider mounted.
    for (final c in _campaigns.where((c) => c.trigger == 'time_on_page')) {
      final seconds = int.tryParse(c.triggerValue ?? '') ?? 10;
      final wait = Duration(seconds: seconds) - DateTime.now().difference(_startedAt);
      _timers.add(Timer(wait.isNegative ? Duration.zero : wait, () => _fire(c)));
    }
    _schedulePageLoad();
  }

  Future<List<KerabieCampaign>> _fetch(KerabieApi api) async {
    try {
      final res = await api.get('/public/campaigns', query: {'widgetKey': controller.config.widgetKey});
      final raw = res['campaigns'];
      return raw is List ? raw.map(KerabieCampaign.fromServer).whereType<KerabieCampaign>().toList() : const [];
    } on KerabieException {
      return const [];
    }
  }

  void _onController() {
    if (!_ready) return;
    if (controller.screen != _lastScreen) {
      _lastScreen = controller.screen;
      _schedulePageLoad();
    }
    if (controller.isOpen != _lastOpen) {
      _lastOpen = controller.isOpen;
      _syncShowing();
    }
  }

  /// A screen appearing: each time the screen changes, campaigns for it get their chance.
  void _schedulePageLoad() {
    _pageLoadTimer?.cancel();
    _pageLoadTimer = Timer(pageLoadDelay, () {
      for (final c in _campaigns.where((c) => c.trigger == 'page_load')) {
        _fire(c);
      }
    });
  }

  void _fire(KerabieCampaign c) {
    if (_disposed || _queued.contains(c.id) || controller.isOpen) return;
    final ok = kerabieIsEligible(
      c,
      KerabieEligibility(
        screen: controller.screen,
        now: _now(),
        returning: _returning,
        hasChatted: controller.hasChatted,
        lastShownAt: _seen['${c.id}'] == null ? null : DateTime.fromMillisecondsSinceEpoch(_seen['${c.id}']!),
        shownThisLaunch: _queued.contains(c.id),
      ),
    );
    if (!ok) return;
    _queued.add(c.id);
    _queue.add(c);
    _syncShowing();
    notifyListeners();
  }

  /// Reports and arms the auto hide for the head of the queue once it is on screen.
  void _syncShowing() {
    final c = current;
    if (c == null) {
      _hideTimer?.cancel();
      _showingId = null;
      notifyListeners();
      return;
    }
    if (_showingId == c.id) return;
    _showingId = c.id;
    if (_reported.add(c.id)) {
      _report(c.id, 'shown');
      _seen = {..._seen, '${c.id}': _now().millisecondsSinceEpoch};
      controller.storage.writeForever(_seenKey, _seen);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(autoHide, () => _remove(c.id));
    notifyListeners();
  }

  void _remove(int id) {
    _queue.removeWhere((c) => c.id == id);
    if (_showingId == id) _showingId = null;
    _syncShowing();
    notifyListeners();
  }

  /// Fire and forget: a failed report must never get in the user's way.
  void _report(int id, String event) {
    controller.waitForApi().then((api) => api.post('/public/campaigns/$id/events', {'widgetKey': controller.config.widgetKey, 'event': event})).then((_) {}, onError: (_) {});
  }

  void dismiss() {
    final c = current;
    if (c != null) _remove(c.id);
  }

  /// The visitor tapped the message or its button: that is "opened", and a reply if they write back.
  void engage({required bool withClick}) {
    final c = current;
    if (c == null) return;
    _report(c.id, 'opened');
    if (withClick) _report(c.id, 'clicked');
    _engagedId = c.id;
    dismiss();
  }

  /// The first message after engaging with a campaign counts as its reply.
  void noteReply() {
    final id = _engagedId;
    if (id == null) return;
    _engagedId = null;
    _report(id, 'replied');
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onController);
    if (controller.onVisitorMessage == noteReply) controller.onVisitorMessage = null;
    for (final t in _timers) {
      t.cancel();
    }
    _pageLoadTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }
}
