import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'models.dart';

/// Something the server pushed. Names are the SDK's own: `connect`, `disconnect`, `ready`, `message`,
/// `typing`, `read`, `agents`, `status`, `start`, `chunk`, and `call_ringing`, `call_queued`, `call_accepted`
/// and `call_ended`.
class KerabieEvent {
  const KerabieEvent(this.name, [this.data = const {}]);

  final String name;
  final Map<String, dynamic> data;
}

/// The live connection to the inbox. [SocketIoRealtime] is the real one; tests use a fake.
abstract class KerabieRealtime {
  Stream<KerabieEvent> get events;
  bool get isConnected;

  void connect({
    required String baseUrl,
    required int orgId,
    required String sessionId,
    required String appName,
    required String appVersion,
    required String appBuild,
    KerabieUser? user,
  });

  /// A null [conversationId] starts a new conversation; the server creates it and echoes the message back.
  void sendMessage({int? conversationId, required String body});
  void sendTyping(int conversationId, bool typing);
  void disconnect();
  void dispose();
}

/// Talks to the `/chat` namespace over Socket.IO.
class SocketIoRealtime implements KerabieRealtime {
  io.Socket? _socket;
  final _controller = StreamController<KerabieEvent>.broadcast();

  @override
  Stream<KerabieEvent> get events => _controller.stream;

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  void connect({
    required String baseUrl,
    required int orgId,
    required String sessionId,
    required String appName,
    required String appVersion,
    required String appBuild,
    KerabieUser? user,
  }) {
    _socket?.dispose();
    final socket = io.io(
      '$baseUrl/chat',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'role': 'visitor'})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setRandomizationFactor(0.5)
          // The client caches sockets by host and port; a fresh one per connect keeps these options in effect.
          .enableForceNew()
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      socket.emit('visitor:init', {
        'orgId': orgId,
        'sessionId': sessionId,
        'name': user?.name,
        'email': user?.email,
        'customData': {
          'appName': appName,
          'appVersion': appVersion,
          'appBuild': appBuild,
          ...?user?.customAttributes,
        },
      });
      _controller.add(const KerabieEvent('connect'));
    });
    socket.onDisconnect((_) => _controller.add(const KerabieEvent('disconnect')));

    void forward(String serverEvent, String name) {
      socket.on(serverEvent, (data) {
        _controller.add(KerabieEvent(name, data is Map ? Map<String, dynamic>.from(data) : const {}));
      });
    }

    forward('visitor:ready', 'ready');
    forward('chat:message', 'message');
    forward('chat:typing', 'typing');
    forward('chat:read', 'read');
    forward('agents:online', 'agents');
    forward('chat:status_change', 'status');
    forward('chat:message:start', 'start');
    forward('chat:message:chunk', 'chunk');
    forward('call:ringing', 'call_ringing');
    forward('call:queued', 'call_queued');
    forward('call:accepted', 'call_accepted');
    forward('call:ended', 'call_ended');

    socket.connect();
  }

  @override
  void sendMessage({int? conversationId, required String body}) {
    _socket?.emit('visitor:message', {'conversationId': conversationId, 'body': body});
  }

  @override
  void sendTyping(int conversationId, bool typing) {
    _socket?.emit('chat:typing', {'conversationId': conversationId, 'typing': typing});
  }

  @override
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  @override
  void dispose() {
    disconnect();
    _controller.close();
  }
}
