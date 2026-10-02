import '../app/persistent_plan_state.dart';
import '../app/save_request.dart';
import '../backup_file/backup_file_gateway.dart';
import 'backup_import_result.dart';
import 'backup_v1_codec.dart';

enum BackupTransferStatus { success, cancelled, candidate, error }

enum BackupTransferError { unavailable, encoding, restore, unexpected }

/// Candidate means validation completed, never that data was saved or adopted.
class BackupTransferResult {
  const BackupTransferResult._(
    this.status, {
    this.candidate,
    this.fileError,
    this.importIssue,
    this.error,
    this.saveFailure,
  });

  final BackupTransferStatus status;
  final BackupImportSuccess? candidate;
  final BackupFileError? fileError;
  final BackupImportIssue? importIssue;
  final BackupTransferError? error;
  final SaveRequestFailure? saveFailure;
}

/// Production orchestration. Presentation only calls these methods and handles
/// results. Confirmation belongs BETWEEN readCandidate and restore; invalid
/// files cannot reach that confirmation. No direct repository writes occur here.
class BackupTransfer {
  BackupTransfer({
    required this.state,
    BackupFileGateway? gateway,
    DateTime Function()? now,
  }) : _gateway = gateway ?? BackupFileGateway(),
       _now = now ?? DateTime.now;

  final PersistentPlanState state;
  final BackupFileGateway _gateway;
  final DateTime Function() _now;
  static const _codec = BackupV1Codec();
  bool _busy = false;

  Future<BackupTransferResult> export() async {
    if (_busy || !state.canExportBackup) return _unavailable();
    _busy = true;
    try {
      final time = _now();
      final bytes = _codec.encode(state.snapshot, createdAt: time);
      final result = await _gateway.save(
        filename: _filename(time.toLocal()),
        mimeType: 'application/octet-stream',
        bytes: bytes,
      );
      return _fileResult(result);
    } catch (_) {
      return const BackupTransferResult._(
        BackupTransferStatus.error,
        error: BackupTransferError.encoding,
      );
    } finally {
      _busy = false;
    }
  }

  Future<BackupTransferResult> readCandidate() async {
    if (_busy || !state.canRestoreBackup) return _unavailable();
    _busy = true;
    try {
      final file = await _gateway.read();
      if (file.status != BackupFileStatus.success) return _fileResult(file);
      final decoded = _codec.decode(file.bytes!);
      return switch (decoded) {
        BackupImportSuccess() => BackupTransferResult._(
          BackupTransferStatus.candidate,
          candidate: decoded,
        ),
        BackupImportFailure(:final issue) => BackupTransferResult._(
          BackupTransferStatus.error,
          importIssue: issue,
        ),
      };
    } catch (_) {
      return const BackupTransferResult._(
        BackupTransferStatus.error,
        error: BackupTransferError.unexpected,
      );
    } finally {
      _busy = false;
    }
  }

  /// Call only after any required replacement confirmation. Cancelling that
  /// confirmation simply discards the candidate, without calling restore.
  Future<BackupTransferResult> restore(BackupImportSuccess candidate) async {
    if (_busy || !state.canRestoreBackup) return _unavailable();
    _busy = true;
    try {
      await state.restoreFromBackup(candidate);
      return const BackupTransferResult._(BackupTransferStatus.success);
    } on SaveRequestFailure catch (failure) {
      return BackupTransferResult._(
        BackupTransferStatus.error,
        error: BackupTransferError.restore,
        saveFailure: failure,
      );
    } catch (_) {
      return const BackupTransferResult._(
        BackupTransferStatus.error,
        error: BackupTransferError.unexpected,
      );
    } finally {
      _busy = false;
    }
  }

  static BackupTransferResult _unavailable() => const BackupTransferResult._(
    BackupTransferStatus.error,
    error: BackupTransferError.unavailable,
  );

  static BackupTransferResult _fileResult(BackupFileResult file) =>
      BackupTransferResult._(switch (file.status) {
        BackupFileStatus.success => BackupTransferStatus.success,
        BackupFileStatus.cancelled => BackupTransferStatus.cancelled,
        BackupFileStatus.error => BackupTransferStatus.error,
      }, fileError: file.error);

  static String _filename(DateTime time) {
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return 'KeepMyCar_Backup_${pad(time.year, 4)}${pad(time.month, 2)}'
        '${pad(time.day, 2)}_${pad(time.hour, 2)}${pad(time.minute, 2)}'
        '${pad(time.second, 2)}.kmcbackup';
  }
}
