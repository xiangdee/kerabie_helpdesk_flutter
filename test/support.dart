import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kerabie_helpdesk_flutter/kerabie_helpdesk_flutter.dart';
import 'package:kerabie_helpdesk_flutter/src/api_client.dart';
import 'package:kerabie_helpdesk_flutter/src/attachments.dart';
import 'package:kerabie_helpdesk_flutter/src/config.dart' show kerabieDefaultBaseUrl;
import 'package:kerabie_helpdesk_flutter/src/realtime.dart';
import 'package:kerabie_helpdesk_flutter/src/storage.dart';

/// A picker that hands out the files a test gives it, without opening anything.
class FakeFilePicker implements KerabieFilePicker {
  KerabiePickedFile? image;
  KerabiePickedFile? document;

  @override
  Future<KerabiePickedFile?> pickImage() async => image;

  @override
  Future<KerabiePickedFile?> pickDocument() async => document;
}

/// A stand-in for the socket: records what the SDK sends and lets a test push server events.
class FakeRealtime implements KerabieRealtime {
  final _events = StreamController<KerabieEvent>.broadcast(sync: true);
  final sent = <({int? conversationId, String body, String? type, String? key, String? fileName})>[];
  /// The guided-flow buttons tapped, in order.
  final choices = <KerabieChoice>[];
  final pages = <({String path, String? previous})>[];
  final pageExits = <String>[];
  final typing = <({int conversationId, bool typing})>[];
  Map<String, Object?>? connectArgs;
  bool connected = false;

  @override
  Stream<KerabieEvent> get events => _events.stream;

  @override
  bool get isConnected => connected;

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
    connected = true;
    connectArgs = {'baseUrl': baseUrl, 'orgId': orgId, 'sessionId': sessionId, 'appName': appName, 'appVersion': appVersion, 'user': user?.name};
  }

  @override
  void sendMessage({int? conversationId, required String body, String? attachmentType, String? attachmentKey, String? attachmentName, KerabieChoice? choice}) {
    sent.add((conversationId: conversationId, body: body, type: attachmentType, key: attachmentKey, fileName: attachmentName));
    if (choice != null) choices.add(choice);
  }

  @override
  void sendPage({required String path, String? title, String? previousPath, int? timeSpentMs}) => pages.add((path: path, previous: previousPath));

  @override
  void sendPageExit({required String path, required int timeSpentMs}) => pageExits.add(path);

  @override
  void sendTyping(int conversationId, bool typing) => this.typing.add((conversationId: conversationId, typing: typing));

  @override
  void disconnect() {}

  @override
  void dispose() => _events.close();

  void emit(String name, [Map<String, dynamic> data = const {}]) => _events.add(KerabieEvent(name, data));
}

/// Routes like `GET /public/widget/init` mapped to a JSON body. Anything else answers 404.
class FakeServer {
  FakeServer(this.routes);

  final Map<String, Object> routes;
  final requests = <http.Request>[];

  http.Client get client => MockClient((req) async {
        requests.add(req);
        final body = routes['${req.method} ${req.url.path}'];
        if (body == null) return http.Response(jsonEncode({'message': 'not found'}), 404);
        if (body is http.Response Function(http.Request)) return body(req);
        if (body is Future<http.Response> Function(http.Request)) return body(req);
        return http.Response(jsonEncode(body), 200);
      });

  http.Request? last(String method, String path) {
    for (final r in requests.reversed) {
      if (r.method == method && r.url.path == path) return r;
    }
    return null;
  }
}

const sampleConfig = KerabieConfig(widgetKey: 'wk_test', appName: 'Test app', appVersion: '1.2.3');

Map<String, dynamic> serverMessage(
  int id,
  String body, {
  String role = 'agent',
  int conversationId = 7,
  Map<String, dynamic>? metadata,
  String? streamId,
}) =>
    {
      'id': id,
      'conversationId': conversationId,
      'body': body,
      'senderRole': role,
      'createdAt': '2026-10-19T09:00:00Z',
      'type': 'text',
      if (metadata != null) 'metadata': metadata,
      if (streamId != null) 'streamId': streamId,
    };

KerabieController makeController({
  required FakeRealtime realtime,
  required FakeServer server,
  KerabieConfig config = sampleConfig,
  Duration sendTimeout = const Duration(milliseconds: 40),
  KerabieFilePicker? filePicker,
  KerabieUploader? uploader,
  String Function()? generateSession,
}) {
  return KerabieController(
    config: config,
    realtime: realtime,
    filePicker: filePicker,
    uploader: uploader,
    storage: KerabieStorage(generate: generateSession ?? () => 'ks_fixed'),
    sendTimeout: sendTimeout,
    apiFactory: (sid) => KerabieApi(baseUrl: kerabieDefaultBaseUrl, widgetKey: config.widgetKey, sessionId: sid, client: server.client),
  );
}
