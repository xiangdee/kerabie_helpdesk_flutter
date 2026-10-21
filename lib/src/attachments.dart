import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'api_client.dart';
import 'models.dart';

/// Mirrors the server's list of allowed attachment types.
const _allowedMime = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'application/pdf',
  'text/plain',
  'text/csv',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/zip',
};

/// 25 MB, the same limit as the server.
const kerabieMaxAttachmentBytes = 25 * 1024 * 1024;

/// Opens the photo library or the document picker. Tests replace it; apps normally use [DeviceFilePicker].
abstract class KerabieFilePicker {
  /// Null when the visitor cancels.
  Future<KerabiePickedFile?> pickImage();
  Future<KerabiePickedFile?> pickDocument();
}

class DeviceFilePicker implements KerabieFilePicker {
  @override
  Future<KerabiePickedFile?> pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return null;
    final name = file.name.isNotEmpty ? file.name : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return KerabiePickedFile(
      path: file.path,
      name: name,
      mimeType: file.mimeType ?? lookupMimeType(name) ?? lookupMimeType(file.path) ?? 'image/jpeg',
      size: await file.length(),
    );
  }

  @override
  Future<KerabiePickedFile?> pickDocument() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final path = file.path ?? file.xFile.path;
    return KerabiePickedFile(
      path: path,
      name: file.name,
      mimeType: lookupMimeType(file.name) ?? lookupMimeType(path) ?? 'application/octet-stream',
      size: await file.xFile.length(),
    );
  }
}

/// What an upload leaves on the server. The attachment is private: [key] is all the server needs to find it again.
@immutable
class KerabieUploadedAttachment {
  const KerabieUploadedAttachment({required this.key, required this.fileName, required this.mimeType});

  final String key;
  final String fileName;
  final String mimeType;
}

/// Checks a file, uploads it and waits until the server has stored it. Throws [KerabieException] with a message
/// fit to show the visitor.
Future<KerabieUploadedAttachment> uploadAttachment(
  KerabieApi api,
  KerabiePickedFile file, {
  Duration pollInterval = const Duration(milliseconds: 700),
  Duration timeout = const Duration(seconds: 30),
}) async {
  final size = file.size;
  if (size != null && size > kerabieMaxAttachmentBytes) {
    throw KerabieException('File is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Maximum is 25 MB.');
  }
  if (!_allowedMime.contains(file.mimeType)) {
    throw KerabieException('File type "${file.mimeType}" is not allowed');
  }

  final started = await api.postFile('/public/widget/attachment',
      field: 'file', filePath: file.path, fileName: file.name, mimeType: file.mimeType);
  final jobId = started['jobId'];
  if (jobId == null) throw KerabieException('Upload failed');

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final job = await api.get('/public/widget/attachment/$jobId');
    final result = job['result'];
    if (job['status'] == 'succeeded' && result is Map) {
      return KerabieUploadedAttachment(
        key: '${result['key']}',
        fileName: '${result['fileName'] ?? file.name}',
        mimeType: '${result['mimeType'] ?? file.mimeType}',
      );
    }
    if (job['status'] == 'failed') {
      throw KerabieException(job['error'] is String && (job['error'] as String).isNotEmpty ? job['error'] as String : 'Upload processing failed');
    }
    await Future<void>.delayed(pollInterval);
  }
  throw KerabieException('Upload timed out');
}

/// Uploads one picked file. [uploadAttachment] is the real one; tests hand in a stand-in.
typedef KerabieUploader = Future<KerabieUploadedAttachment> Function(KerabieApi api, KerabiePickedFile file);

/// A picked file uploads in the background and waits for Send, so a caption can go with it. The search bar and the
/// chat screen share one staging area: a file picked in the bar is still there, already uploaded, when the chat opens.
class KerabieAttachmentStaging extends ChangeNotifier {
  KerabieAttachmentStaging({this.errorDuration = const Duration(seconds: 5), KerabieUploader? uploader})
      : _uploader = uploader ?? ((api, file) => uploadAttachment(api, file));

  final Duration errorDuration;
  final KerabieUploader _uploader;

  KerabiePickedFile? _pending;
  KerabieUploadedAttachment? _uploaded;
  bool _isUploading = false;
  String? _error;
  Timer? _errorTimer;
  bool _disposed = false;

  /// The file the visitor picked, while it uploads and until it is sent or removed.
  KerabiePickedFile? get pending => _pending;

  /// Set once the upload finished: this is what [KerabieController.sendMessage] sends.
  KerabieUploadedAttachment? get uploaded => _uploaded;
  bool get isUploading => _isUploading;
  String? get error => _error;

  Future<void> stage(KerabieApi? api, KerabiePickedFile? file) async {
    if (file == null) return;
    _uploaded = null;
    _pending = file;
    _isUploading = true;
    _notify();
    try {
      if (api == null) throw KerabieException('The chat has not started yet.');
      final uploaded = await _uploader(api, file);
      // The visitor may have removed it, or picked another, while it uploaded.
      if (identical(_pending, file)) _uploaded = uploaded;
    } on KerabieException catch (e) {
      showError(e.message);
      if (identical(_pending, file)) _pending = null;
    } catch (_) {
      showError('Could not upload attachment');
      if (identical(_pending, file)) _pending = null;
    } finally {
      if (identical(_pending, file) || _pending == null) _isUploading = false;
      _notify();
    }
  }

  void remove() {
    _pending = null;
    _uploaded = null;
    _isUploading = false;
    _notify();
  }

  /// Clears the staging area once its attachment has been handed to a message.
  void consume() => remove();

  void showError(String message) {
    _error = message;
    _errorTimer?.cancel();
    _errorTimer = Timer(errorDuration, dismissError);
    _notify();
  }

  void dismissError() {
    _errorTimer?.cancel();
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _errorTimer?.cancel();
    super.dispose();
  }
}
