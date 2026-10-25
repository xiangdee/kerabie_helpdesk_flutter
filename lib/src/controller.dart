import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'attachments.dart';
import 'config.dart';
import 'deep_link.dart';
import 'guided.dart';
import 'models.dart';
import 'realtime.dart';
import 'storage.dart';

/// Which push service issued the token you register. These are the values the Kerabie API accepts.
/// Use one provider for the whole app: Kerabie keeps a single token per visitor session.
enum KerabiePushProvider { fcm, expo }

/// The first message of a new conversation, still waiting for the server to say which conversation it made.
class _DraftConversation {
  _DraftConversation(this.tempId);

  final String tempId;
  final Completer<int?> id = Completer<int?>();
}

/// A screen path the server accepts: it starts with a slash.
String kerabieScreenPath(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '/';
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

/// The state of the chat and the actions on it. Rebuilds listeners when anything changes.
class KerabieController extends ChangeNotifier {
  KerabieController({
    required this.config,
    KerabieStorage? storage,
    KerabieRealtime? realtime,
    KerabieApi Function(String sessionId)? apiFactory,
    KerabieFilePicker? filePicker,
    KerabieUploader? uploader,
    this.sendTimeout = const Duration(seconds: 8),
  })  : _storage = storage ?? KerabieStorage(),
        _realtime = realtime ?? SocketIoRealtime(),
        filePicker = filePicker ?? DeviceFilePicker(),
        staging = KerabieAttachmentStaging(uploader: uploader),
        _user = config.user,
        _appVersion = config.appVersion,
        _apiFactory = apiFactory ??
            ((sessionId) => KerabieApi(baseUrl: kerabieDefaultBaseUrl, widgetKey: config.widgetKey, sessionId: sessionId));

  final KerabieConfig config;

  /// Opens the photo library and the document picker for attachments.
  final KerabieFilePicker filePicker;

  /// The file the visitor picked and is about to send. Shared by the chat screen and the search bar.
  final KerabieAttachmentStaging staging;

  /// How long a sent message may stay unconfirmed before it is marked failed.
  final Duration sendTimeout;

  final KerabieStorage _storage;
  final KerabieRealtime _realtime;
  final KerabieApi Function(String sessionId) _apiFactory;

  KerabieApi? _api;
  final _apiReady = Completer<KerabieApi>();
  StreamSubscription<KerabieEvent>? _events;
  String? _sessionId;
  int _orgId = 0;
  bool _started = false;
  bool _disposed = false;
  bool _hasReadyBefore = false;

  final List<KerabieMessage> _messages = [];
  final Map<String, String> _pendingBodies = {};
  final Map<String, Timer> _failTimers = {};
  _DraftConversation? _draftConversation;
  Timer? _typingTimer;
  int _localCounter = 0;
  int? _conversationId;

  KerabieSettings _settings = const KerabieSettings();
  KerabieUser? _user;
  String _appVersion;
  List<KerabieConversation> _conversations = const [];
  String? _chatDraft;
  bool _isConnected = false;
  bool _isOpen = false;
  bool _isTyping = false;
  bool _isAiTyping = false;
  int _unreadCount = 0;
  int? _agentsOnline;
  String? _screen;
  DateTime? _screenSince;

  /// Set by [KerabieProvider]: shows the chat over the app. A link or a notification tap uses it.
  void Function(KerabieRoute route)? presenter;

  /// Set by whoever shows the chat, so [toggle] and [dismissChat] can take it away again.
  VoidCallback? dismisser;

  /// Called when the app should open the chat in its own navigator ([KerabieOpenMode.push]).
  void Function(KerabieRoute route)? onNavigate;
  VoidCallback? onOpenChat;
  VoidCallback? onCloseChat;

  /// A campaign button can open your knowledge base. Chat has no fixed screen for it, so the app decides where it goes.
  VoidCallback? onOpenKnowledgeBase;

  /// Runs when the visitor sends a message. Campaigns use it to count a reply.
  VoidCallback? onVisitorMessage;

  List<KerabieMessage> get messages => List.unmodifiable(_messages);

  /// What the dashboard has saved for this widget.
  KerabieSettings get settings => _settings;

  /// The chat settings in force: the dashboard's, with anything you set in [KerabieConfig.chatSettings] on top.
  KerabieChatSettings get chat => _settings.chat.merge(config.chatSettings);

  bool get isConnected => _isConnected;
  bool get isOpen => _isOpen;
  bool get isTyping => _isTyping;
  bool get isAiTyping => _isAiTyping;
  int get unreadCount => _unreadCount;

  /// Agents online right now, when the server has said. Null until it has.
  int? get agentsOnline => _agentsOnline;
  int? get conversationId => _conversationId;
  String? get sessionId => _sessionId;

  /// What the SDK remembers on the device.
  KerabieStorage get storage => _storage;

  /// The REST client, once the chat has started. The ticket, knowledge base and store screens use it.
  KerabieApi? get api => _api;

  /// The REST client, waiting for the chat to start if it has not yet.
  Future<KerabieApi> waitForApi() async => _api ?? await _apiReady.future;

  /// Who the customer is, as far as the app has said.
  KerabieUser? get currentUser => _user;

  /// The identified user's name, used to fill `{{name}}` in the welcome message. Empty when unknown.
  String get visitorName => _user?.name ?? '';

  String get appName => config.appName;
  String get appVersion => _appVersion;
  String get appBuild => config.appBuild;

  /// The visitor's conversations, after [refreshConversations].
  List<KerabieConversation> get conversations => _conversations;

  /// Text typed into the search bar, waiting for the chat screen to send it.
  String? get chatDraft => _chatDraft;

  /// The screen the app reported with [trackScreen], as a path such as `/checkout`.
  String? get screen => _screen;

  /// The visitor has written, or been written to: campaigns for people who have not chatted yet stay quiet.
  bool get hasChatted => _messages.isNotEmpty || _conversationId != null || _conversations.isNotEmpty;

  /// Loads the history and the dashboard settings, then connects. Safe to call more than once.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final sessionId = await _storage.sessionId();
    if (_disposed) return;
    _sessionId = sessionId;
    _api = _apiFactory(sessionId);
    _apiReady.complete(_api);
    _events = _realtime.events.listen(_onEvent);

    await _loadHistory(replace: true);
    _orgId = await _loadSettings();
    if (_disposed) return;

    final user = _user;
    if (user != null) unawaited(identify(user));
    _connect();
  }

  void _connect() {
    _realtime.connect(
      baseUrl: kerabieDefaultBaseUrl,
      orgId: _orgId,
      sessionId: _sessionId!,
      appName: config.appName,
      appVersion: _appVersion,
      appBuild: config.appBuild,
      user: _user,
    );
  }

  Future<void> _loadHistory({required bool replace, int? conversationId}) async {
    try {
      final res = await _api!.get(
        '/public/widget/messages',
        query: conversationId == null ? null : {'conversationId': '$conversationId'},
      );
      final raw = res['messages'];
      if (raw is! List) return;
      // A conversation that is not this visitor's comes back empty; keep what is on screen.
      if (conversationId != null && res['conversationId'] is! num) return;
      final loaded = raw.whereType<Map>().map((m) => KerabieMessage.fromServer(Map<String, dynamic>.from(m))).toList();
      if (res['conversationId'] is num) _conversationId = (res['conversationId'] as num).toInt();
      if (replace) {
        _messages
          ..clear()
          ..addAll(loaded);
      } else {
        // After a reconnect, pick up what arrived while offline. The visitor's own messages are already shown.
        var fresh = 0;
        for (final m in loaded) {
          if (!m.isFromVisitor && !_messages.any((x) => x.id == m.id)) {
            _messages.add(m);
            fresh++;
          }
        }
        if (!_isOpen) _unreadCount += fresh;
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

  /// Loads the visitor's conversations into [conversations].
  Future<void> refreshConversations() async {
    try {
      final res = await _api?.get('/public/widget/conversations');
      final raw = res?['conversations'];
      if (raw is! List) return;
      _conversations = raw.map(KerabieConversation.fromServer).whereType<KerabieConversation>().toList();
      _notify();
    } on KerabieException {
      // Keep the list we have.
    }
  }

  // ─── Identity ─────────────────────────────────────────────────────────────────

  /// Tells Kerabie who this visitor is. Called for you when [KerabieConfig.user] is set.
  Future<void> identify(KerabieUser user) async {
    try {
      await _api?.post('/public/widget/identify', {'user': user.toJson()});
    } on KerabieException {
      // Identification is best effort; chat works without it.
    }
  }

  /// Call after login so agents see who they are talking to.
  Future<void> setUser(KerabieUser user) async {
    _user = user;
    _notify();
    await identify(user);
  }

  /// Call after logout. The conversation on screen is cleared and the next visitor starts a fresh anonymous session.
  Future<void> clearUser() async {
    _user = null;
    _messages.clear();
    _conversationId = null;
    _conversations = const [];
    _unreadCount = 0;
    _agentsOnline = null;
    _chatDraft = null;
    _clearPending();
    _clearTyping();
    staging.remove();
    _notify();
    if (!_started || _disposed) return;
    _realtime.disconnect();
    await _storage.clear();
    final sessionId = await _storage.sessionId();
    if (_disposed) return;
    _sessionId = sessionId;
    _api?.close();
    _api = _apiFactory(sessionId);
    _hasReadyBefore = false;
    _connect();
  }

  /// Adds one detail agents see next to the customer, for example `plan: pro`.
  Future<void> updateAttribute(String key, String value) async {
    final user = _user ?? const KerabieUser();
    final updated = user.copyWith(customAttributes: {...user.customAttributes, key: value});
    _user = updated;
    _notify();
    await identify(updated);
  }

  /// Tells Kerabie the app's version changed. It is sent with the next connection.
  void setAppVersion(String version) {
    _appVersion = version;
    _notify();
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
    final id = KerabieDeepLink.conversationIdFromNotification(data);
    if (id == null) return false;
    _openConversation(id);
    return true;
  }

  /// Call with an incoming link. Returns true when it was a Kerabie conversation link and the chat was opened.
  bool handleDeepLink(Uri uri) {
    final id = KerabieDeepLink.conversationId(uri, scheme: config.deepLinkScheme);
    if (id == null) return false;
    _openConversation(id);
    return true;
  }

  void _openConversation(int id) {
    if (id != _conversationId && _started) unawaited(_loadHistory(replace: true, conversationId: id));
    showChat(route: KerabieRoute(KerabieRouteType.conversation, conversationId: id));
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
    final opening = !_isOpen;
    _isOpen = true;
    _unreadCount = 0;
    _notify();
    if (opening) {
      onOpenChat?.call();
      if (_messages.isEmpty) refreshGuidedGreeting();
    }
  }

  KerabieGuidedGreeting? _greeting;
  bool _greetingAsked = false;

  /// The question and buttons the organisation's chat flow opens with, for the screen the visitor is on now.
  /// Starts as what the widget settings carried, and is asked for again each time an empty chat opens, because
  /// the flow can differ by screen.
  KerabieGuidedGreeting? get guidedGreeting => _greetingAsked ? _greeting : chat.guidedGreeting;

  /// Asks the server for the opening question of this screen. A failed request keeps what is shown.
  Future<void> refreshGuidedGreeting() async {
    try {
      final res = await _api?.get('/public/widget/greeting');
      if (res == null) return;
      _greeting = KerabieGuidedGreeting.fromServer(res['guidedGreeting']);
      _greetingAsked = true;
      _notify();
    } on KerabieException {
      // Keep what is on screen.
    }
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    _notify();
    onCloseChat?.call();
  }

  /// Shows the chat screen over the app. Needs the navigator key passed to [KerabieProvider]; without one, only the
  /// state changes and your own UI shows the chat. With [KerabieOpenMode.push] your [onNavigate] is called instead.
  void showChat({KerabieRoute route = const KerabieRoute(KerabieRouteType.inbox)}) {
    final present = presenter;
    if (present != null) {
      present(route);
    } else {
      open();
    }
  }

  /// Takes the chat screen away again.
  void dismissChat() {
    final dismiss = dismisser;
    if (dismiss != null) {
      dismiss();
    } else {
      close();
    }
  }

  void toggle() => _isOpen ? dismissChat() : showChat();

  /// The search bar opens the chat with what was typed. The chat screen sends it.
  void openWithDraft(String text) {
    _chatDraft = text;
    _notify();
    showChat();
  }

  void clearChatDraft() {
    if (_chatDraft == null) return;
    _chatDraft = null;
    _notify();
  }

  /// Opens the chat and tells the agent what the customer was looking at: an order, a product, a payment.
  /// Set [KerabieChatContext.openChat] to false to only record it.
  void openWithContext(KerabieChatContext context) {
    final api = _api;
    if (api == null) return;
    // Fire and forget: a failed report must not stop the chat from opening.
    unawaited(api.post('/public/widget/context', {
      'contextType': context.type,
      'contextId': context.id,
      'contextTitle': context.title,
      'contextData': context.data,
    }).then((_) {}, onError: (_) {}));
    if (context.openChat) showChat();
  }

  // ─── Screens ──────────────────────────────────────────────────────────────────

  /// Tells Kerabie which screen the customer is on, as a path such as `/checkout`. Agents see the page the customer
  /// is on, and campaigns can be limited to certain screens. [KerabieNavigatorObserver] calls this for you.
  void trackScreen(String path, {String? title}) {
    final next = kerabieScreenPath(path);
    final previous = _screen;
    if (next == previous) return;
    final now = DateTime.now();
    if (previous != null && _screenSince != null) {
      _realtime.sendPageExit(path: previous, timeSpentMs: now.difference(_screenSince!).inMilliseconds);
    }
    _screen = next;
    _screenSince = now;
    _realtime.sendPage(path: next, title: title, previousPath: previous);
    _notify();
  }

  // ─── Attachments ──────────────────────────────────────────────────────────────

  /// Opens the photo library and stages the picked photo for the next message.
  Future<void> pickPhoto() => _pick(filePicker.pickImage, 'Could not open photo library');

  /// Opens the document picker and stages the picked file for the next message.
  Future<void> pickDocument() => _pick(filePicker.pickDocument, 'Could not open document picker');

  Future<void> _pick(Future<KerabiePickedFile?> Function() picker, String failure) async {
    try {
      final file = await picker();
      await staging.stage(_api, file);
    } catch (e) {
      staging.showError(e is KerabieException ? e.message : failure);
    }
  }

  // ─── Sending ──────────────────────────────────────────────────────────────────

  /// Sends [text]. A photo or file staged with [pickPhoto] or [pickDocument] goes with it as the caption's attachment.
  /// Does nothing while that file is still uploading.
  ///
  /// A [choice] marks a tap on a guided flow's button: [text] is then the button's label.
  Future<void> sendMessage(String text, {KerabieAttachment? attachment, KerabieChoice? choice}) async {
    final body = text.trim();
    var attached = attachment;
    if (attached == null && staging.pending != null) {
      final file = staging.pending!;
      final uploaded = staging.uploaded;
      if (staging.isUploading || uploaded == null) return;
      attached = KerabieAttachment(
        url: file.path,
        key: uploaded.key,
        type: uploaded.mimeType.startsWith('image/') ? 'image' : 'file',
        name: uploaded.fileName,
      );
      staging.consume();
    }
    if (body.isEmpty && attached == null) return;

    onVisitorMessage?.call();
    var conversationId = _conversationId;
    // The first message of a conversation is still on its way: wait for its id, so this one joins the same conversation.
    if (conversationId == null && _draftConversation != null) conversationId = await _draftConversation!.id.future;

    final tempId = 'local_${++_localCounter}';
    final message = KerabieMessage(
      id: tempId,
      conversationId: conversationId,
      body: body,
      createdAt: DateTime.now(),
      sender: KerabieSender.visitor,
      status: KerabieMessageStatus.pending,
      type: attached?.type ?? 'text',
      metadata: attached == null ? const {} : {'url': attached.url, 'fileName': attached.name},
      attachment: attached,
    );
    _messages.add(message);

    if (!_realtime.isConnected) {
      _replace(tempId, (m) => m.copyWith(status: KerabieMessageStatus.failed));
      _notify();
      return;
    }

    _pendingBodies[tempId] = body;
    if (conversationId == null) _draftConversation = _DraftConversation(tempId);
    _failTimers[tempId] = Timer(sendTimeout, () => _markFailed(tempId));
    _notify();
    _realtime.sendMessage(
      conversationId: conversationId,
      body: body,
      attachmentType: attached?.type,
      attachmentKey: attached?.key,
      attachmentName: attached?.name,
      choice: choice,
    );
  }

  /// Sends a failed message again.
  Future<void> retry(KerabieMessage message) async {
    if (message.status != KerabieMessageStatus.failed) return;
    _messages.removeWhere((m) => m.id == message.id);
    await sendMessage(message.body, attachment: message.attachment);
  }

  void sendTyping(bool typing) {
    final id = _conversationId;
    if (id != null) _realtime.sendTyping(id, typing);
  }

  void _markFailed(String tempId) {
    _failTimers.remove(tempId)?.cancel();
    if (_draftConversation?.tempId == tempId) {
      _draftConversation!.id.complete(null);
      _draftConversation = null;
    }
    if (!_pendingBodies.containsKey(tempId)) return;
    _pendingBodies.remove(tempId);
    _replace(tempId, (m) => m.copyWith(status: KerabieMessageStatus.failed));
    _notify();
  }

  void _clearPending() {
    for (final timer in _failTimers.values) {
      timer.cancel();
    }
    _failTimers.clear();
    _pendingBodies.clear();
    if (_draftConversation?.id.isCompleted == false) _draftConversation!.id.complete(null);
    _draftConversation = null;
  }

  // ─── Events from the server ───────────────────────────────────────────────────

  void _onEvent(KerabieEvent event) {
    switch (event.name) {
      case 'connect':
        _isConnected = true;
        final screen = _screen;
        if (screen != null) _realtime.sendPage(path: screen);
      case 'disconnect':
        _isConnected = false;
        _clearTyping();
      case 'ready':
        final id = event.data['conversationId'];
        if (id is num) _conversationId ??= id.toInt();
        final online = event.data['agentsOnline'];
        // Only a boolean here; `agents` carries the real count later.
        if (online is bool) _agentsOnline = online ? ((_agentsOnline ?? 0) > 0 ? _agentsOnline : 1) : 0;
        // The socket does not replay what was sent while it was down, so ask for the history again after a reconnect.
        if (_hasReadyBefore) unawaited(_loadHistory(replace: false));
        _hasReadyBefore = true;
      case 'agents':
        final count = event.data['count'];
        if (count is num) _agentsOnline = count.toInt();
      case 'message':
        _onMessage(event.data);
      case 'linkpreview':
        final preview = KerabieLinkPreview.fromServer(event.data['linkPreview']);
        if (preview != null) _replace('${event.data['messageId']}', (m) => m.copyWith(linkPreview: preview));
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

    // The echo of a new conversation's first message is the earliest the server's conversation id is known.
    final draft = _draftConversation;
    if (draft != null && message.conversationId != null && _pendingBodies[draft.tempId] == message.body) {
      _draftConversation = null;
      draft.id.complete(message.conversationId);
    }
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
    _clearPending();
    _events?.cancel();
    _callEvents.close();
    staging.dispose();
    _realtime.dispose();
    _api?.close();
    super.dispose();
  }
}
