import 'dart:typed_data';

import '../app/persistent_plan_state.dart';
import '../app/save_request.dart';
import '../backup_file/backup_file_gateway.dart';
import '../persistence/keep_my_car_data_mapper.dart';
import '../photo/photo_library.dart';
import '../photo/photo_processor.dart';
import 'zip_backup_result.dart';
import 'zip_backup_worker.dart';

enum ZipTransferStatus {
  exportReady,
  photoConfirmation,
  importConfirmation,
  success,
  cancelled,
  conflict,
  unavailable,
  error,
}

enum ZipTransferError { photo, codec, save, unexpected }

/// Opaque, identity checked, single-use. Only this library can issue tokens.
final class ZipBackupToken {
  ZipBackupToken._();
}

class ZipTransferResult {
  const ZipTransferResult(
    this.status, {
    this.token,
    this.plan,
    this.hasPhoto = false,
    this.photoStatus,
    this.fileError,
    this.codecIssue,
    this.error,
    this.saveFailure,
  });
  final ZipTransferStatus status;
  final ZipBackupToken? token;
  // Immutable preview only; apply APIs never accept caller-supplied candidates.
  final RestoredCarData? plan;
  final bool hasPhoto;
  final BackupPhotoStatus? photoStatus;
  final BackupFileError? fileError;
  final ZipBackupIssue? codecIssue;
  final ZipTransferError? error;
  final SaveRequestFailure? saveFailure;
}

class _Operation {
  bool cancelled = false;
  bool committing = false;
  final cancellation = PhotoCancellation();
}

class _Pending {
  _Pending(
    this.operation,
    this.generation,
    this.phase,
    this.plan,
    this.jpeg, {
    required this.importing,
    this.photoStatus,
  });
  final token = ZipBackupToken._();
  final _Operation operation;
  final int generation;
  final StartupPhase phase;
  final RestoredCarData plan;
  final Uint8List? jpeg;
  final bool importing;
  final BackupPhotoStatus? photoStatus;
}

/// Technical API for F-Impl-06. Confirmation is split from I/O/application.
/// Own one alongside JSON BackupTransfer; both use state.backupOperations.
class ZipBackupTransfer {
  ZipBackupTransfer({
    required this.state,
    BackupFileGateway? gateway,
    ZipBackupWorker? worker,
    DateTime Function()? now,
  }) : _gateway = gateway ?? BackupFileGateway(),
       _worker = worker ?? ZipBackupWorker(),
       _now = now ?? DateTime.now {
    state.addListener(_changed);
  }

  final PersistentPlanState state;
  final BackupFileGateway _gateway;
  final ZipBackupWorker _worker;
  final DateTime Function() _now;
  _Operation? _operation;
  _Pending? _pending;
  bool _disposed = false;

  static const _conflict = ZipTransferResult(ZipTransferStatus.conflict);
  static const _unavailable = ZipTransferResult(ZipTransferStatus.unavailable);
  static const _cancelled = ZipTransferResult(ZipTransferStatus.cancelled);

  _Operation? _start(bool importing) {
    if (_disposed ||
        _operation != null ||
        !(importing ? state.canRestoreBackup : state.canExportBackup)) {
      return null;
    }
    final operation = _Operation();
    if (!state.backupOperations.acquire(operation)) return null;
    _operation = operation;
    return operation;
  }

  bool _live(_Operation operation) =>
      !_disposed &&
      !state.isDisposed &&
      identical(_operation, operation) &&
      !operation.cancelled;

  bool _matches(_Pending pending) =>
      state.generation == pending.generation &&
      state.phase == pending.phase &&
      (pending.importing ? state.canRestoreBackup : state.canExportBackup);

  void _finish(_Operation operation) {
    state.backupOperations.release(operation);
    if (identical(_operation, operation)) {
      _operation = null;
      _pending = null;
    }
  }

  void _changed() {
    final pending = _pending;
    // Busy alone is transient (e.g. cleanup), not a formal-state revision.
    if (pending != null &&
        (state.generation != pending.generation ||
            state.phase != pending.phase ||
            (pending.importing
                ? state.saveRestricted
                : state.versionProtection != null))) {
      _finish(pending.operation);
    }
  }

  /// In-flight workers/I/O retain the shared gate until they actually return.
  /// Once Safe Save is accepted it must finish; cancellation is then rejected.
  ZipTransferResult cancel() {
    final operation = _operation;
    if (_disposed || operation == null || operation.committing) {
      return _unavailable;
    }
    operation.cancelled = true;
    operation.cancellation.cancel();
    if (_pending != null) _finish(operation);
    return _cancelled;
  }

  Future<ZipTransferResult> prepareExport() async {
    final operation = _start(false);
    if (operation == null) return _unavailable;
    PhotoLease? lease;
    try {
      // No await between snapshot capture and synchronous protection.
      final plan = state.snapshot;
      final generation = state.generation;
      final phase = state.phase;
      Uint8List? jpeg;
      BackupPhotoStatus? photoStatus;
      if (plan.photoId != null) {
        final photos = state.photos;
        if (photos == null) {
          return const ZipTransferResult(
            ZipTransferStatus.error,
            error: ZipTransferError.photo,
            photoStatus: BackupPhotoStatus.unavailable,
          );
        }
        lease = photos.protect(plan.photoId!);
        final photo = await photos.readForBackup(plan.photoId!);
        if (!_live(operation)) return _cancelled;
        photoStatus = photo.status;
        switch (photo.status) {
          case BackupPhotoStatus.available:
            jpeg = photo.jpeg!;
          case BackupPhotoStatus.missing || BackupPhotoStatus.corrupt:
            break;
          default:
            return ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.photo,
              photoStatus: photo.status,
            );
        }
      }
      if (!_live(operation)) return _cancelled;
      final pending = _Pending(
        operation,
        generation,
        phase,
        plan,
        jpeg,
        importing: false,
        photoStatus: photoStatus,
      );
      if (!_matches(pending)) return _conflict;
      _pending = pending;
      return ZipTransferResult(
        photoStatus == BackupPhotoStatus.missing ||
                photoStatus == BackupPhotoStatus.corrupt
            ? ZipTransferStatus.photoConfirmation
            : ZipTransferStatus.exportReady,
        token: pending.token,
        plan: plan,
        hasPhoto: jpeg != null,
        photoStatus: photoStatus,
      );
    } on PhotoFailure catch (failure) {
      return failure.issue == PhotoIssue.busy
          ? _unavailable
          : const ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.photo,
            );
    } catch (_) {
      return const ZipTransferResult(
        ZipTransferStatus.error,
        error: ZipTransferError.unexpected,
      );
    } finally {
      lease?.release();
      if (_pending == null) _finish(operation);
    }
  }

  Future<ZipTransferResult> writeExport(
    ZipBackupToken token, {
    bool approvePhotoOmission = false,
  }) async {
    final pending = _pending;
    if (pending == null ||
        pending.importing ||
        !identical(token, pending.token)) {
      return _conflict;
    }
    _pending = null; // Consume before the first await, even on rejection.
    final operation = pending.operation;
    try {
      if (!_live(operation)) return _cancelled;
      if (!_matches(pending)) return _conflict;
      if (pending.photoStatus == BackupPhotoStatus.missing ||
          pending.photoStatus == BackupPhotoStatus.corrupt) {
        if (!approvePhotoOmission) return _cancelled;
      }
      final bytes = await _worker.encode(pending.plan, jpeg: pending.jpeg);
      if (!_live(operation)) return _cancelled;
      if (state.versionProtection != null ||
          (state.phase != StartupPhase.ready &&
              state.phase != StartupPhase.recovered)) {
        return _unavailable;
      }
      // Export uses the already captured snapshot despite later normal edits.
      final filename =
          'KeepMyCar_Backup_${_now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.zip';
      return _file(
        await _gateway.save(
          filename: filename,
          mimeType: 'application/zip',
          bytes: bytes,
        ),
        operation,
      );
    } on ZipBackupFailure catch (failure) {
      if (!_live(operation)) return _cancelled;
      return ZipTransferResult(
        ZipTransferStatus.error,
        error: ZipTransferError.codec,
        codecIssue: failure.issue,
      );
    } catch (_) {
      return _live(operation)
          ? const ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.unexpected,
            )
          : _cancelled;
    } finally {
      _finish(operation);
    }
  }

  Future<ZipTransferResult> readImport() async {
    final operation = _start(true);
    if (operation == null) return _unavailable;
    try {
      final file = await _gateway.readZip();
      if (!_live(operation)) return _cancelled;
      if (file.status != BackupFileStatus.success) {
        return _file(file, operation);
      }
      final result = await _worker.decode(file.bytes!);
      if (!_live(operation)) return _cancelled;
      if (result is ZipBackupFailure) {
        return ZipTransferResult(
          ZipTransferStatus.error,
          error: ZipTransferError.codec,
          codecIssue: result.issue,
        );
      }
      if (!state.canRestoreBackup) return _unavailable;
      final success = result as ZipBackupSuccess;
      final pending = _Pending(
        operation,
        state.generation,
        state.phase,
        success.plan,
        success.jpeg,
        importing: true,
      );
      _pending = pending;
      return ZipTransferResult(
        ZipTransferStatus.importConfirmation,
        token: pending.token,
        plan: pending.plan,
        hasPhoto: pending.jpeg != null,
      );
    } catch (_) {
      return _live(operation)
          ? const ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.unexpected,
            )
          : _cancelled;
    } finally {
      if (_pending == null) _finish(operation);
    }
  }

  Future<ZipTransferResult> confirmImport(ZipBackupToken token) async {
    final pending = _pending;
    if (pending == null ||
        !pending.importing ||
        !identical(token, pending.token)) {
      return _conflict;
    }
    _pending = null;
    final operation = pending.operation;
    PhotoLease? lease;
    try {
      if (!_live(operation)) return _cancelled;
      if (!_matches(pending)) return _conflict;
      String? id;
      if (pending.jpeg != null) {
        final photos = state.photos;
        if (photos == null) {
          return const ZipTransferResult(
            ZipTransferStatus.error,
            error: ZipTransferError.photo,
            photoStatus: BackupPhotoStatus.unavailable,
          );
        }
        id = photos.newId();
        lease = await photos.acquireLease(
          id,
          cancellation: operation.cancellation,
        );
        if (!_live(operation)) return _cancelled;
        await photos.prepareJpeg(id, pending.jpeg!, operation.cancellation);
      }
      if (!_live(operation)) return _cancelled;
      if (!_matches(pending)) return _conflict;
      // No await from revision check to State's synchronous _persist guard.
      operation.committing = true;
      await state.restoreAggregate(
        pending.plan,
        photoId: id,
        expectedGeneration: pending.generation,
      );
      // Normal return means saving and formal adoption both completed, even if
      // this transfer was disposed after the save had been accepted.
      return const ZipTransferResult(ZipTransferStatus.success);
    } on BackupStateChanged {
      return _conflict;
    } on SaveRequestFailure catch (failure) {
      return ZipTransferResult(
        ZipTransferStatus.error,
        error: ZipTransferError.save,
        saveFailure: failure,
      );
    } on PhotoFailure catch (failure) {
      return failure.issue == PhotoIssue.cancelled
          ? _cancelled
          : const ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.photo,
            );
    } catch (_) {
      return _live(operation)
          ? const ZipTransferResult(
              ZipTransferStatus.error,
              error: ZipTransferError.unexpected,
            )
          : _cancelled;
    } finally {
      lease?.release();
      // Never remove the new file merely because save threw. Repository/State
      // decide whether cleanup is safe, including rollback uncertainty/dispose.
      try {
        await state.cleanupPhotos();
      } finally {
        _finish(operation);
      }
    }
  }

  ZipTransferResult _file(BackupFileResult result, _Operation operation) {
    if (!_live(operation)) return _cancelled;
    return ZipTransferResult(switch (result.status) {
      BackupFileStatus.success => ZipTransferStatus.success,
      BackupFileStatus.cancelled => ZipTransferStatus.cancelled,
      BackupFileStatus.error => ZipTransferStatus.error,
    }, fileError: result.error);
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    state.removeListener(_changed);
  }
}
