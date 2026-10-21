import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// The server answered with an error, or could not be reached.
class KerabieException implements Exception {
  KerabieException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => 'KerabieException(${status ?? 'network'}): $message';
}

/// The REST calls the widget makes. Every request carries the widget key and the visitor's session id.
class KerabieApi {
  KerabieApi({required this.baseUrl, required this.widgetKey, required this.sessionId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String widgetKey;
  final String sessionId;
  final http.Client _client;

  Map<String, String> get _headers => {
        'x-widget-key': widgetKey,
        'x-session-id': sessionId,
      };

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return _send(() => _client.get(uri, headers: _headers));
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    return _send(
      () => _client.post(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body)),
    );
  }

  /// Uploads one file as multipart form data under the field [field].
  Future<Map<String, dynamic>> postFile(String path, {required String field, required String filePath, required String fileName, required String mimeType}) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(await http.MultipartFile.fromPath(field, filePath, filename: fileName, contentType: MediaType.parse(mimeType)));
    return _send(() async => http.Response.fromStream(await _client.send(request)));
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    return _send(() => _client.delete(uri, headers: _headers));
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request();
    } catch (e) {
      throw KerabieException('$e');
    }
    Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = decoded is Map && decoded['message'] is String ? decoded['message'] as String : 'HTTP ${res.statusCode}';
      throw KerabieException(message, status: res.statusCode);
    }
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  void close() => _client.close();
}
