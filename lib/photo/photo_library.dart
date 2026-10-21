import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../persistence/storage_format.dart';
import 'photo_file_storage.dart';
import 'photo_processor.dart';

class PhotoLease {
  PhotoLease._(this._release);
  void Function()? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

enum BackupPhotoStatus {
  available,
  missing,
  corrupt,
  ioFailure,
  unsafe,
  unavailable,
}

class BackupPhotoRead {
  const BackupPhotoRead(this.status, [this.jpeg]);
  final BackupPhotoStatus status;
  final Uint8List? jpeg;
}

/// Own one instance per photo directory. Preparation leases protect files until
/// the caller has either finished Safe Save or abandoned its request. Export can
/// use the same lease API without implementing export here.
class PhotoLibrary {
  PhotoLibrary({
    required this.storage,
    required this.processor,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;
  factory PhotoLibrary.applicationSupport({required PhotoInputLimits limits}) =>
      PhotoLibrary(
        storage: IoPhotoFileStorage.applicationSupport(),
        processor: DartPhotoProcessor(limits),
      );
  factory PhotoLibrary.backupApplicationSupport() => PhotoLibrary(
    storage: IoPhotoFileStorage.applicationSupport(),
    processor: StoredJpegProcessor(),
  );
  final PhotoFileStorage storage;
  final PhotoProcessor processor;
  final String Function() _newId;
  final Map<String, int> _leases = {};
  final Map<String, Completer<void>> _preparing = {};
  Completer<void>? _cleanupDone;
  bool get _cleaning => _cleanupDone != null;

  String newId() {
    final id = _newId();
    validatePhotoId(id);
    return id;
  }

  PhotoLease protect(String id) {
    validatePhotoId(id);
    if (_cleaning) throw const PhotoFailure(PhotoIssue.busy);
    _leases.update(id, (count) => count + 1, ifAbsent: () => 1);
    return PhotoLease._(() {
      final count = _leases[id]!;
      if (count == 1) {
        _leases.remove(id);
      } else {
        _leases[id] = count - 1;
      }
    });
  }

  /// Wait for an actual cleanup completion event, never poll or retry I/O.
  /// Recheck after wake-up because another sweep may have acquired the gate.
  Future<PhotoLease> acquireLease(
    String id, {
    PhotoCancellation? cancellation,
  }) async {
    validatePhotoId(id);
    cancellation?.check();
    while (_cleanupDone != null) {
      final running = _cleanupDone!;
      await Future.any<void>([
        running.future,
        if (cancellation != null) cancellation.cancelled,
      ]);
      cancellation?.check();
    }
    return protect(id);
  }

  Future<void> prepare(
    String id,
    String sourcePath,
    PhotoCancellation cancellation,
  ) => _prepare(
    id,
    () => processor.process(sourcePath, cancellation),
    cancellation,
  );

  /// Caller holds an outer lease until Safe Save/abandonment. No recompression.
  Future<void> prepareJpeg(
    String id,
    Uint8List jpeg,
    PhotoCancellation cancellation,
  ) => _prepare(id, () async => jpeg, cancellation);

  Future<void> _prepare(
    String id,
    Future<Uint8List> Function() source,
    PhotoCancellation cancellation,
  ) async {
    final lease = await acquireLease(id, cancellation: cancellation);
    if (_preparing.containsKey(id)) {
      lease.release();
      throw const PhotoFailure(PhotoIssue.busy);
    }
    final done = Completer<void>();
    _preparing[id] = done;
    try {
      cancellation.check();
      final jpeg = await source();
      cancellation.check();
      await storage.writeNew(id, jpeg, processor);
      cancellation.check();
    } finally {
      _preparing.remove(id);
      done.complete();
      lease.release();
    }
  }

  /// Narrow diagnostic contract for backup. Legacy read() keeps its semantics.
  Future<BackupPhotoRead> readForBackup(String id) async {
    PhotoLease? lease;
    try {
      lease = await acquireLease(id);
      while (_preparing.containsKey(id)) {
        await _preparing[id]!.future;
      }
      final bytes = await storage.read(id);
      if (bytes == null) {
        return const BackupPhotoRead(BackupPhotoStatus.missing);
      }
      await processor.validate(bytes);
      return BackupPhotoRead(
        BackupPhotoStatus.available,
        Uint8List.fromList(bytes).asUnmodifiableView(),
      );
    } on FileSystemException {
      return const BackupPhotoRead(BackupPhotoStatus.ioFailure);
    } on PhotoFailure catch (error) {
      return BackupPhotoRead(switch (error.issue) {
        PhotoIssue.invalidImage ||
        PhotoIssue.outputLimit => BackupPhotoStatus.corrupt,
        PhotoIssue.unsafePath => BackupPhotoStatus.unsafe,
        _ => BackupPhotoStatus.unavailable,
      });
    } finally {
      lease?.release();
    }
  }

  /// Missing/corrupt photos never make the plan unreadable. This also protects
  /// against observing an in-progress, not-yet-verified file through this API.
  Future<Uint8List?> read(String id) async {
    PhotoLease? lease;
    try {
      lease = await acquireLease(id);
      while (_preparing.containsKey(id)) {
        final preparing = _preparing[id]!;
        await preparing.future;
      }
      final bytes = await storage.read(id);
      if (bytes == null) return null;
      await processor.validate(bytes);
      return bytes;
    } on PhotoFailure catch (error) {
      switch (error.issue) {
        case PhotoIssue.invalidImage ||
            PhotoIssue.outputLimit ||
            PhotoIssue.unsupported ||
            PhotoIssue.unsafePath:
          return null;
        default:
          rethrow;
      }
    } on FileSystemException {
      return null;
    } finally {
      lease?.release();
    }
  }

  Future<void> cleanup(Set<String> references) async {
    if (_cleaning) throw const PhotoFailure(PhotoIssue.busy);
    final done = Completer<void>();
    _cleanupDone = done;
    try {
      // Synchronous protect rejects and acquireLease waits during the sweep,
      // preventing the check/delete race. Existing leases stay protected.
      await storage.cleanup({...references, ..._leases.keys});
    } finally {
      _cleanupDone = null;
      done.complete();
    }
  }
}
