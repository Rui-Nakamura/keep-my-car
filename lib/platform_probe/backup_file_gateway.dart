import 'package:flutter/services.dart';

enum BackupFileStatus { success, cancelled, error }

enum BackupFileError {
  busy,
  missingUri,
  streamUnavailable,
  ioFailure,
  tooLarge,
  timeout,
  interrupted,
  platformFailure,
  invalidArguments,
  invalidResponse,
}

class BackupFileResult {
  const BackupFileResult._(this.status, {this.bytes, this.error});

  const BackupFileResult.failure(BackupFileError error)
    : this._(BackupFileStatus.error, error: error);

  final BackupFileStatus status;
  final Uint8List? bytes;
  final BackupFileError? error;
}

/// Probe-only transport. Does not decode backups or mutate application state.
class BackupFileGateway {
  final MethodChannel _channel = const MethodChannel(
    'keep_my_car/backup_file_probe',
  );

  Future<BackupFileResult> save({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) => _invoke('save', {
    'filename': filename,
    'mimeType': mimeType,
    'bytes': bytes,
  });

  Future<BackupFileResult> read() => _invoke('read', null);

  Future<BackupFileResult> _invoke(
    String method,
    Map<String, Object>? arguments,
  ) async {
    try {
      // No Future.timeout: time spent in the OS picker is unlimited.
      // Android enforces the deadline only after a URI starts real I/O.
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      if (response is! Map) return _invalid();
      switch (response['status']) {
        case 'success':
          if (response.containsKey('code')) return _invalid();
          if (method == 'read') {
            final bytes = response['bytes'];
            if (bytes is! Uint8List) return _invalid();
            return BackupFileResult._(
              BackupFileStatus.success,
              bytes: Uint8List.fromList(bytes),
            );
          }
          if (response.containsKey('bytes')) return _invalid();
          return const BackupFileResult._(BackupFileStatus.success);
        case 'cancelled':
          if (response.containsKey('bytes') || response.containsKey('code')) {
            return _invalid();
          }
          return const BackupFileResult._(BackupFileStatus.cancelled);
        case 'error':
          if (response.containsKey('bytes')) return _invalid();
          final code = response['code'];
          for (final error in BackupFileError.values) {
            if (code == error.name) return BackupFileResult.failure(error);
          }
          return _invalid();
        default:
          return _invalid();
      }
    } on PlatformException {
      return const BackupFileResult.failure(BackupFileError.platformFailure);
    } on MissingPluginException {
      return const BackupFileResult.failure(BackupFileError.platformFailure);
    } catch (_) {
      return const BackupFileResult.failure(BackupFileError.platformFailure);
    }
  }

  BackupFileResult _invalid() =>
      const BackupFileResult.failure(BackupFileError.invalidResponse);
}
