import 'package:flutter/foundation.dart';

/// Who sent a message.
enum KerabieSender { visitor, agent, bot }

/// Delivery state of a message the visitor sent from this device.
enum KerabieMessageStatus { pending, sent, delivered, read, failed }

/// The person using your app. Pass it in [KerabieConfig.user] so agents see who they are talking to.
@immutable
class KerabieUser {
  const KerabieUser({this.id, this.name, this.email, this.phone, this.role, this.customAttributes = const {}});

  /// Your own id for this user.
  final String? id;
  final String? name;
  final String? email;
  final String? phone;

  /// For example `customer`, `driver` or `admin`.
  final String? role;

  /// Extra details shown to agents, such as a plan or an account id.
  final Map<String, String> customAttributes;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
        if (customAttributes.isNotEmpty) 'customAttributes': customAttributes,
      };

  KerabieUser copyWith({String? id, String? name, String? email, String? phone, String? role, Map<String, String>? customAttributes}) =>
      KerabieUser(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        customAttributes: customAttributes ?? this.customAttributes,
      );
}

/// A file picked to send. Upload it with [KerabieController.stageAttachment]; it goes out with the next message.
@immutable
class KerabiePickedFile {
  const KerabiePickedFile({required this.path, required this.name, required this.mimeType, this.size});

  /// Where the file is on the device.
  final String path;
  final String name;
  final String mimeType;
  final int? size;

  bool get isImage => mimeType.startsWith('image/');
}

/// A file attached to a message being sent. [url] is the file on the device, shown while the message is sent;
/// [key] is what the upload returned and what the server needs.
@immutable
class KerabieAttachment {
  const KerabieAttachment({required this.url, required this.key, required this.type, this.name});

  final String url;
  final String key;

  /// `image` or `file`.
  final String type;
  final String? name;
}

/// A preview of a link in a message, fetched by the server after the message arrives.
@immutable
class KerabieLinkPreview {
  const KerabieLinkPreview({required this.url, required this.title, this.description, this.image, this.favicon, this.siteName});

  final String url;
  final String title;
  final String? description;
  final String? image;
  final String? favicon;
  final String? siteName;

  static KerabieLinkPreview? fromServer(Object? raw) {
    if (raw is! Map || raw['url'] is! String) return null;
    return KerabieLinkPreview(
      url: raw['url'] as String,
      title: '${raw['title'] ?? ''}',
      description: raw['description'] as String?,
      image: raw['image'] as String?,
      favicon: raw['favicon'] as String?,
      siteName: raw['siteName'] as String?,
    );
  }
}

/// A knowledge base article an AI reply was based on.
@immutable
class KerabieCitation {
  const KerabieCitation({required this.id, required this.title});

  final int id;
  final String title;
}

/// One row of the visitor's conversation list, as the server describes it.
@immutable
class KerabieConversation {
  const KerabieConversation({
    required this.id,
    required this.name,
    this.avatar,
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.status = 'open',
  });

  final int id;

  /// The assigned agent, or the widget's agent name.
  final String name;
  final String? avatar;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  /// `open`, `resolved` or `closed`.
  final String status;

  static KerabieConversation? fromServer(Object? raw) {
    if (raw is! Map || raw['id'] is! num) return null;
    return KerabieConversation(
      id: (raw['id'] as num).toInt(),
      name: '${raw['name'] ?? 'Support'}',
      avatar: raw['avatar'] as String?,
      lastMessage: '${raw['lastMessage'] ?? ''}',
      lastMessageTime: DateTime.tryParse('${raw['lastMessageTime']}'),
      unreadCount: (raw['unreadCount'] as num?)?.toInt() ?? 0,
      isOnline: raw['isOnline'] == true,
      status: '${raw['status'] ?? 'open'}'.toLowerCase(),
    );
  }
}

/// What the customer was looking at when they asked for help, so agents do not have to ask.
@immutable
class KerabieChatContext {
  const KerabieChatContext({required this.type, this.id, this.title, this.data, this.openChat = true});

  /// `order`, `product`, `transaction`, `ride`, `errand`, `booking` or `custom`.
  final String type;

  /// Your own reference, for example an order number.
  final String? id;

  /// A short label the agent sees, for example `Order #2024-001`.
  final String? title;

  /// Any extra details, such as a price or a status.
  final Map<String, dynamic>? data;

  /// Set false to only record the context and open the chat later.
  final bool openChat;
}

/// A call, and the pass that lets the app join its LiveKit room. The optional `kerabie_helpdesk_flutter_calls`
/// package turns this into audio and video; this package only carries it.
@immutable
class KerabieCallJoin {
  const KerabieCallJoin({
    required this.callId,
    required this.status,
    required this.video,
    required this.livekitUrl,
    required this.livekitToken,
    this.handler,
    this.queuePosition,
  });

  final int callId;

  /// `QUEUED`, `RINGING` or `ACTIVE`.
  final String status;
  final bool video;

  /// `HUMAN` or `AI`, once somebody has answered.
  final String? handler;

  /// Place in the queue (1 = next), only while the call is waiting.
  final int? queuePosition;
  final String livekitUrl;
  final String livekitToken;

  factory KerabieCallJoin.fromServer(Map<String, dynamic> json) {
    final livekit = json['livekit'] is Map ? Map<String, dynamic>.from(json['livekit'] as Map) : const <String, dynamic>{};
    return KerabieCallJoin(
      callId: (json['callId'] as num).toInt(),
      status: '${json['status'] ?? 'QUEUED'}',
      video: json['video'] == true,
      handler: json['handler'] as String?,
      queuePosition: (json['queuePosition'] as num?)?.toInt(),
      livekitUrl: '${livekit['url'] ?? ''}',
      livekitToken: '${livekit['token'] ?? ''}',
    );
  }
}

/// Where a call stands, pushed by the server: `ringing`, `queued`, `accepted` or `ended`.
@immutable
class KerabieCallEvent {
  const KerabieCallEvent(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;

  int? get callId => (data['callId'] as num?)?.toInt();
}

/// One message in the conversation.
@immutable
class KerabieMessage {
  const KerabieMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.sender,
    this.conversationId,
    this.senderName,
    this.senderAvatar,
    this.status = KerabieMessageStatus.sent,
    this.streaming = false,
    this.streamId,
    this.type = 'text',
    this.metadata = const {},
    this.linkPreview,
    this.attachment,
  });

  /// Server ids are numbers; local, not-yet-sent messages use `local_<n>`.
  final String id;
  final int? conversationId;
  final String body;
  final DateTime createdAt;
  final KerabieSender sender;
  final String? senderName;
  final String? senderAvatar;
  final KerabieMessageStatus status;

  /// True while an AI reply is still arriving word by word.
  final bool streaming;
  final String? streamId;

  /// `text`, `image`, `file`, `audio`, `video` or `system`.
  final String type;
  final Map<String, dynamic> metadata;

  /// Arrives after the message, once the server has fetched the first link in it.
  final KerabieLinkPreview? linkPreview;

  /// Set on a message this device is sending, so a failed one can be sent again.
  final KerabieAttachment? attachment;

  /// Where an attached image or file can be opened from. On a message still being sent this is the file on the device.
  String? get attachmentUrl => metadata['url'] is String ? metadata['url'] as String : null;
  String? get attachmentName => metadata['fileName'] is String ? metadata['fileName'] as String : null;

  /// The knowledge base articles an AI reply was based on.
  List<KerabieCitation> get citations {
    final articles = metadata['articles'];
    if (articles is! List) return const [];
    return [
      for (final a in articles)
        if (a is Map && a['id'] is num) KerabieCitation(id: (a['id'] as num).toInt(), title: '${a['title'] ?? ''}'),
    ];
  }

  bool get isFromVisitor => sender == KerabieSender.visitor;

  /// Builds a message from the server's wire format. The server says `senderRole: customer | agent`;
  /// an AI reply is an agent message whose `metadata.source` is `ai`.
  factory KerabieMessage.fromServer(Map<String, dynamic> raw) {
    final metadata = raw['metadata'] is Map ? Map<String, dynamic>.from(raw['metadata'] as Map) : <String, dynamic>{};
    final sender = raw['senderRole'] == 'customer'
        ? KerabieSender.visitor
        : metadata['source'] == 'ai'
            ? KerabieSender.bot
            : KerabieSender.agent;
    return KerabieMessage(
      id: '${raw['id']}',
      conversationId: (raw['conversationId'] as num?)?.toInt(),
      body: (raw['body'] ?? '') as String,
      createdAt: DateTime.tryParse('${raw['createdAt']}') ?? DateTime.now(),
      sender: sender,
      senderName: raw['senderName'] as String?,
      senderAvatar: raw['senderAvatar'] as String?,
      streamId: raw['streamId']?.toString(),
      type: (raw['type'] ?? 'text') as String,
      metadata: metadata,
      linkPreview: KerabieLinkPreview.fromServer(raw['linkPreview']),
      status: switch (raw['status']) {
        'delivered' => KerabieMessageStatus.delivered,
        'read' => KerabieMessageStatus.read,
        _ => KerabieMessageStatus.sent,
      },
    );
  }

  KerabieMessage copyWith({
    String? id,
    String? body,
    KerabieMessageStatus? status,
    bool? streaming,
    int? conversationId,
    KerabieLinkPreview? linkPreview,
  }) {
    return KerabieMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      body: body ?? this.body,
      createdAt: createdAt,
      sender: sender,
      senderName: senderName,
      senderAvatar: senderAvatar,
      status: status ?? this.status,
      streaming: streaming ?? this.streaming,
      streamId: streamId,
      type: type,
      metadata: metadata,
      linkPreview: linkPreview ?? this.linkPreview,
      attachment: attachment,
    );
  }
}
