import 'package:flutter/foundation.dart';

/// Who sent a message.
enum KerabieSender { visitor, agent, bot }

/// Delivery state of a message the visitor sent from this device.
enum KerabieMessageStatus { pending, sent, failed }

/// The person using your app. Pass it in [KerabieConfig.user] so agents see who they are talking to.
@immutable
class KerabieUser {
  const KerabieUser({this.id, this.name, this.email, this.phone, this.customAttributes = const {}});

  /// Your own id for this user.
  final String? id;
  final String? name;
  final String? email;
  final String? phone;

  /// Extra details shown to agents, such as a plan or an account id.
  final Map<String, String> customAttributes;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (customAttributes.isNotEmpty) 'customAttributes': customAttributes,
      };
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
    this.status = KerabieMessageStatus.sent,
    this.streaming = false,
    this.streamId,
    this.type = 'text',
    this.metadata = const {},
  });

  /// Server ids are numbers; local, not-yet-sent messages use `local_<n>`.
  final String id;
  final int? conversationId;
  final String body;
  final DateTime createdAt;
  final KerabieSender sender;
  final String? senderName;
  final KerabieMessageStatus status;

  /// True while an AI reply is still arriving word by word.
  final bool streaming;
  final String? streamId;

  /// `text`, `image`, `file`, `audio`, `video` or `system`.
  final String type;
  final Map<String, dynamic> metadata;

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
      streamId: raw['streamId']?.toString(),
      type: (raw['type'] ?? 'text') as String,
      metadata: metadata,
    );
  }

  KerabieMessage copyWith({
    String? id,
    String? body,
    KerabieMessageStatus? status,
    bool? streaming,
    int? conversationId,
  }) {
    return KerabieMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      body: body ?? this.body,
      createdAt: createdAt,
      sender: sender,
      senderName: senderName,
      status: status ?? this.status,
      streaming: streaming ?? this.streaming,
      streamId: streamId,
      type: type,
      metadata: metadata,
    );
  }
}
