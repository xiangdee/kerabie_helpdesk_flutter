import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'config.dart';
import 'deep_link.dart';
import 'models.dart';
import 'realtime.dart';
import 'storage.dart';

/// Which push service issued the token you register. These are the values the Kerabie API accepts.
/// Use one provider for the whole app: Kerabie keeps a single token per visitor session.
enum KerabiePushProvider { fcm, expo }

/// The state of the chat and the actions on it. Rebuilds listeners when anything changes.
class KerabieController extends ChangeNotifier {
  KerabieController({
    required this.config,
    KerabieStorage? storage,
    KerabieRealtime? realtime,
    KerabieApi Function(String sessionId)? apiFactory,
    this.sendTimeout = const Duration(seconds: 10),
  })  : _storage = storage ?? KerabieStorage(),
        _realtime = realtime ?? SocketIoRealtime(),
        _apiFactory = apiFactory ??
            ((sessionId) => KerabieApi(baseUrl: config.baseUrl, widgetKey: config.widgetKey, sessionId: sessionId));

  final KerabieConfig config;

  /// How long a sent message may stay unconfirmed before it is marked failed.
  final Duration sendTimeout;

  final KerabieStorage _storage;
  final KerabieRealtime _realtime;
  final KerabieApi Function(String sessionId) _apiFactory;

  KerabieApi? _api;
  StreamSubscription<KerabieEvent>? _events;
  String? _sessionId;
  bool _started = false;
  bool _disposed = false;
  bool _hasConnectedBefore = false;

  final List<KerabieMessage> _messages = [];
  final Map<String, String> _pendingBodies = {};
  final Map<String, Timer> _failTimers = {};
  Timer? _typingTimer;
  int _localCounter = 0;
  int? _conversationId;

  KerabieSettings _settings = const KerabieSettings();
  bool _isConnected = false;
  bool _isOpen = false;
  bool _isTyping = false;
  bool _isAiTyping = false;
  int _unreadCount = 0;
  int? _agentsOnline;

  /// Set by [KerabieProvider] when it was given a navigator key, so a link or a notification tap can show the chat.
  VoidCallback? presenter;

  List<KerabieMessage> get messages => List.unmodifiable(_messages);
  KerabieSettings get settings => _settings;
  bool get isConnected => _isConnected;
  bool get isOpen => _isOpen;
  bool get isTyping => _isTyping;
  bool get isAiTyping => _isAiTyping;
  int get unreadCount => _unreadCount;

  /// Agents online right now, when the server has said. Null until it has.
  int? get agentsOnline => _agentsOnline;
  int? get conversationId => _conversationId;
  String? get sessionId => _sessionId;

  /// Loads the history and the dashboard settings, then connects. Safe to call more than once.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final sessionId = await _storage.sessionId();
    if (_disposed) return;
    _sessionId = sessionId;
    _api = _apiFactory(sessionId);
    _events = _realtime.events.listen(_onEvent);

    await _loadHistory(replace: true);
    final orgId = await _loadSettings();
    if (_disposed) return;

    final user = config.user;
    if (user != null) unawaited(identify(user));

    _realtime.connect(
      baseUrl: config.baseUrl,
      orgId: orgId,
      sessionId: sessionId,
      appName: config.appName,
      appVersion: config.appVersion,
      appBuild: config.appBuild,
      user: user,
    );
  }

  Future<void> _loadHistory({required bool replace}) async {
    try {
      final res = await _api!.get('/public/widget/messages');
      final raw = res['messages'];
      if (raw is! List) return;
      final loaded = raw.whereType<Map>().map((m) => KerabieMessage.fromServer(Map<String, dynamic>.from(m))).toList();
      if (res['conversationId'] is num) _conversationId = (res['conversationId'] as num).toInt();
      if (replace) {
        _messages
          ..clear()
          ..addAll(loaded);
      } else {
        // After a reconnect, pick up what arrived while offline. The visitor's own messages are already shown.
        for (final m in loaded) {
          if (!m.isFromVisitor && !_messages.any((x) => x.id == m.id)) _messages.add(m);
        }
      }
      _notify();
    } on KerabieException {
      // No history yet is fine; the conversation starts with the first message.
    }
  }

  /// Returns the organisation id the socket needs (0 when the settings could not be loaded, as in the other SDKs).
  Future<int> _loadSettings() async {
    try {
      final res = await _api!.get('/public/widget/init');
      final settings = res['settings'];
      if (settings is Map) {
        _settings = KerabieSettings.fromServer(Map<String, dynamic>.from(settings));
        _notify();
      }
      return (res['orgId'] as num?)?.toInt() ?? 0;
    } on KerabieException {
      return 0;
    }
  }

  /// Tells Kerabie who this visitor is. Called for you when [KerabieConfig.user] is set.
  Future<void> identify(KerabieUser user) async {
    try {
      await _api?.post('/public/widget/identify', {'user': user.toJson()});
    } on KerabieException {
      // Identification is best effort; chat works without it.
    }
  }

  // ─── Push notifications ───────────────────────────────────────────────────────

  /// Registers this device's push token so Kerabie can notify the visitor. Pass the token from the one push
  /// service your app uses, with its [provider]. Returns whether Kerabie accepted it.
  Future<bool> registerPushToken(String token, {required KerabiePushProvider provider}) async {
    try {
      final res = await _api?.post('/public/widget/push-token', {'token': token, 'provider': provider.name});
      return res?['success'] == true;
    } on KerabieException {
      return false;
    }
  }

  /// Call with a notification's data when the user taps it. Returns true when it pointed at a Kerabie conversation
  /// and the chat was opened.
  bool handleNotificationData(Map<String, dynamic> data) {
    if (KerabieDeepLink.conversationIdFromNotification(data) == null) return false;
    showChat();
    return true;
  }

  /// Call with an incoming link. Returns true when it was a Kerabie conversation link and the chat was opened.
  bool handleDeepLink(Uri uri) {
    if (KerabieDeepLink.conversationId(uri, scheme: config.deepLinkScheme) == null) return false;
    showChat();
    return true;
  }

  // ─── Calls ────────────────────────────────────────────────────────────────────
  // Only the requests and events live here, so apps that just want chat carry no call code. The optional
  // `kerabie_helpdesk_flutter_calls` package adds the audio, video and screens.

  final _callEvents = StreamController<KerabieCallEvent>.broadcast();

  /// Where the current call stands, pushed by the server: `ringing`, `queued`, `accepted` and `ended`.
  Stream<KerabieCallEvent> get callEvents => _callEvents.stream;

  /// Starts a call. A visitor who already has one is put back into it. Throws [KerabieException] when calls are off,
  /// the plan has no minutes left or the visitor is starting too many.
  Future<KerabieCallJoin> startCall({bool video = false}) async {
    final api = _api;
    if (api == null) throw KerabieException('The chat has not started yet.');
    final res = await api.post('/public/widget/calls', {'video': video && _settings.videoCallsEnabled});
    return KerabieCallJoin.fromServer(res);
  }

  /// The call this visitor is in right now, if any, so an app that was closed can rejoin it.
  Future<KerabieCallJoin?> currentCall() async {
    final api = _api;
    if (api == null) return null;
    final res = await api.get('/public/widget/calls/current');
    final call = res['call'];
    return call is Map ? KerabieCallJoin.fromServer(Map<String, dynamic>.from(call)) : null;
  }

  /// Hangs up, or cancels a call nobody has answered yet.
  Future<void> endCall(int callId) async {
    await _api?.post('/public/widget/calls/$callId/end', {});
  }

  // ─── Opening and closing ──────────────────────────────────────────────────────

  /// Marks the chat as open and clears the unread count. The chat screen calls this itself.
  void open() {
    if (_isOpen && _unreadCount == 0) return;
    _isOpen = true;
    _unreadCount = 0;
    _notify();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    _notify();
  }

  /// Shows the chat screen over the app. Needs the navigator key passed to [KerabieProvider]; without one, only the
  /// state changes and your own UI shows the chat.
  void showChat() {
    final present = presenter;
    if (present != null) {
      present();
    } else {
      open();
    }
  }

  // ─── Sending ──────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final tempId = 'local_${++_localCounter}';
    _messages.add(KerabieMessage(
      id: tempId,
      conversationId: _conversationId,
      body: body,
      createdAt: DateTime.now(),
      sender: KerabieSender.visitor,
      status: KerabieMessageStatus.pending,
    ));
    _pendingBodies[tempId] = body;
    _failTimers[tempId] = Timer(sendTimeout, () => _markFailed(tempId));
    _notify();
    _realtime.sendMessage(conversationId: _conversationId, body: body);
  }

  /// Sends a failed message again.
  Future<void> retry(KerabieMessage message) async {
    if (message.status != KerabieMessageStatus.failed) return;
    _messages.removeWhere((m) => m.id == message.id);
    await sendMessage(message.body);
  }

  void sendTyping(bool typing) {
    final id = _conversationId;
    if (id != null) _realtime.sendTyping(id, typing);
  }

  void _markFailed(String tempId) {
    _failTimers.remove(tempId)?.cancel();
    if (!_pendingBodies.containsKey(tempId)) return;
    _pendingBodies.remove(tempId);
    _replace(tempId, (m) => m.copyWith(status: KerabieMessageStatus.failed));
    _notify();
  }

  // ─── Events from the server ───────────────────────────────────────────────────

  void _onEvent(KerabieEvent event) {
    switch (event.name) {
      case 'connect':
        _isConnected = true;
        if (_hasConnectedBefore) unawaited(_loadHistory(replace: false));
        _hasConnectedBefore = true;
      case 'disconnect':
        _isConnected = false;
        _clearTyping();
      case 'ready':
        final id = event.data['conversationId'];
        if (id is num) _conversationId ??= id.toInt();
        final online = event.data['agentsOnline'];
        // Only a boolean here; `agents` carries the real count later.
        if (online is bool) _agentsOnline = online ? ((_agentsOnline ?? 0) > 0 ? _agentsOnline : 1) : 0;
      case 'agents':
        final count = event.data['count'];
        if (count is num) _agentsOnline = count.toInt();
      case 'message':
        _onMessage(event.data);
      case 'start':
        _onStreamStart(event.data);
      case 'chunk':
        _onStreamChunk(event.data);
      case 'typing':
        _onTyping(event.data);
      case 'call_ringing' || 'call_queued' || 'call_accepted' || 'call_ended':
        _callEvents.add(KerabieCallEvent(event.name.substring('call_'.length), event.data));
        return; // no chat state changed
      default:
        return;
    }
    _notify();
  }

  void _onMessage(Map<String, dynamic> raw) {
    final message = KerabieMessage.fromServer(raw);
    if (message.conversationId != null) _conversationId ??= message.conversationId;

    // The final text of an AI reply that was streaming in.
    final streamId = message.streamId;
    if (streamId != null) {
      final i = _messages.indexWhere((m) => m.id == 'stream_$streamId');
      if (i >= 0) {
        _messages[i] = message;
        _afterIncoming(message);
        return;
      }
    }

    // The server's copy of a message this device sent: replace the local one.
    if (message.isFromVisitor) {
      final tempId = _pendingBodies.entries.where((e) => e.value == message.body).map((e) => e.key).firstOrNull;
      if (tempId != null) {
        _pendingBodies.remove(tempId);
        _failTimers.remove(tempId)?.cancel();
        _replace(tempId, (_) => message.copyWith(status: KerabieMessageStatus.sent));
        return;
      }
    }

    if (_messages.any((m) => m.id == message.id)) return;
    _messages.add(message);
    _afterIncoming(message);
  }

  void _afterIncoming(KerabieMessage message) {
    if (message.isFromVisitor) return;
    _clearTyping();
    if (!_isOpen) _unreadCount++;
  }

  void _onStreamStart(Map<String, dynamic> data) {
    final streamId = data['streamId']?.toString();
    if (streamId == null) return;
    final id = 'stream_$streamId';
    if (_messages.any((m) => m.id == id)) return;
    _messages.add(KerabieMessage(
      id: id,
      body: '',
      createdAt: DateTime.now(),
      sender: KerabieSender.bot,
      senderName: (data['senderName'] as String?) ?? 'AI Assistant',
      streaming: true,
      streamId: streamId,
    ));
    _isAiTyping = false;
    _isTyping = false;
  }

  void _onStreamChunk(Map<String, dynamic> data) {
    final id = 'stream_${data['streamId']}';
    final delta = data['delta'];
    if (delta is! String) return;
    _replace(id, (m) => m.copyWith(body: m.body + delta));
  }

  void _onTyping(Map<String, dynamic> data) {
    _typingTimer?.cancel();
    _typingTimer = null;
    final typing = data['typing'] != false;
    // User id 0 is the AI assistant's typing identity.
    final fromAi = data['userId'] == 0;
    if (!typing) {
      _isTyping = false;
      _isAiTyping = false;
      return;
    }
    _isTyping = true;
    _isAiTyping = fromAi;
    // Safety net in case the matching "stopped typing" never arrives.
    _typingTimer = Timer(fromAi ? const Duration(seconds: 30) : const Duration(seconds: 3), () {
      _isTyping = false;
      _isAiTyping = false;
      _notify();
    });
  }

  void _clearTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    _isTyping = false;
    _isAiTyping = false;
  }

  void _replace(String id, KerabieMessage Function(KerabieMessage) change) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i >= 0) _messages[i] = change(_messages[i]);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _typingTimer?.cancel();
    for (final timer in _failTimers.values) {
      timer.cancel();
    }
    _failTimers.clear();
    _events?.cancel();
    _callEvents.close();
    _realtime.dispose();
    _api?.close();
    super.dispose();
  }
}
