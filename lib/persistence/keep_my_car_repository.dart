import 'dart:convert';

import 'keep_my_car_data_mapper.dart';
import 'keep_my_car_json_codec.dart';
import 'local_file_storage.dart';
import 'persistence_result.dart';

/// One owner per storage directory. Concurrent operations on this instance are
/// rejected, including load during save, so no intermediate state is exposed.
/// This is not a cross-process transaction or a power-loss durability guarantee.
class KeepMyCarRepository {
  KeepMyCarRepository(this._storage);

  final LocalFileStorage _storage;
  static const _mapper = KeepMyCarDataMapper();
  static const _codec = KeepMyCarJsonCodec();
  bool _busy = false;

  PersistenceIssue _busyIssue() => PersistenceIssue(
    PersistenceStage.busy,
    StateError('A persistence operation is already running'),
    StackTrace.current,
  );

  RestoredCarData _decode(List<int> bytes) =>
      _mapper.toDomain(_codec.decode(utf8.decode(bytes)));

  List<int> _encode(RestoredCarData data) => utf8.encode(
    _codec.encode(
      _mapper.toDto(
        ownerBirthMonth: data.ownerBirthMonth,
        car: data.car,
        planConditions: data.planConditions,
        plannedExpenses: data.plannedExpenses,
      ),
    ),
  );

  Future<LoadResult> load() async {
    if (_busy) return LoadFailure([_busyIssue()]);
    _busy = true;
    final issues = <PersistenceIssue>[];
    try {
      try {
        final current = await _storage.read(DataFile.current);
        if (current != null) return Loaded(_decode(current));
      } catch (error, stack) {
        issues.add(
          PersistenceIssue(PersistenceStage.readCurrent, error, stack),
        );
      }
      try {
        final backup = await _storage.read(DataFile.backup);
        if (backup != null) {
          return Recovered(
            _decode(backup),
            currentIssue: issues.isEmpty ? null : issues.first,
          );
        }
      } catch (error, stack) {
        issues.add(PersistenceIssue(PersistenceStage.readBackup, error, stack));
      }
      // Temp is never read, promoted or deleted during load.
      return issues.isEmpty ? const NoData() : LoadFailure(issues);
    } finally {
      _busy = false;
    }
  }

  Future<SaveResult> save(RestoredCarData snapshot) async {
    if (_busy) return SaveFailure(_busyIssue());
    _busy = true;
    var stage = PersistenceStage.encode;
    List<int>? oldCurrent;
    List<int>? oldBackup;
    var rotating = false;
    var mutationStarted = false;
    try {
      // Encode before the first await: later caller list changes cannot change
      // the candidate that is being committed.
      final candidate = _encode(snapshot);
      stage = PersistenceStage.prepare;
      await _storage.prepare();
      stage = PersistenceStage.writeTemp;
      await _storage.writeTemp(candidate);
      stage = PersistenceStage.verifyTemp;
      await _verify(DataFile.temp, candidate);

      stage = PersistenceStage.readCurrent;
      oldCurrent = await _storage.read(DataFile.current);
      if (oldCurrent != null) {
        try {
          _decode(oldCurrent);
          rotating = true;
        } on FormatException {
          // Never rotate corrupt/unsupported data over a potentially good backup.
        } on ArgumentError {
          // Fixed domain validation failed; keep existing backup untouched.
        }
      }
      if (rotating) {
        stage = PersistenceStage.readBackup;
        oldBackup = await _storage.read(DataFile.backup);
        stage = PersistenceStage.backupCurrent;
        mutationStarted = true;
        await _storage.move(DataFile.current, DataFile.backup);
        await _verify(DataFile.backup, oldCurrent!);
      }
      stage = PersistenceStage.promoteTemp;
      mutationStarted = true;
      await _storage.move(DataFile.temp, DataFile.current);
      stage = PersistenceStage.verifyCurrent;
      await _verify(DataFile.current, candidate);
      return const Saved();
    } catch (error, stack) {
      final rollbackIssues = <PersistenceIssue>[];
      if (mutationStarted) {
        // File.rename may remove the destination before failing. Restore from
        // captured bytes, through temp, even if a move threw after taking effect.
        // Restore current first. If this fails, leave backup (the prior normal
        // current) alone so that the next load can still recover from it.
        try {
          await _restore(DataFile.current, oldCurrent);
          if (rotating) await _restore(DataFile.backup, oldBackup);
        } catch (rollbackError, rollbackStack) {
          rollbackIssues.add(
            PersistenceIssue(
              PersistenceStage.rollback,
              rollbackError,
              rollbackStack,
            ),
          );
        }
      }
      return SaveFailure(
        PersistenceIssue(stage, error, stack),
        rollbackIssues: rollbackIssues,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _verify(DataFile file, List<int> expected) async {
    final bytes = await _storage.read(file);
    if (bytes == null) {
      throw StateError('Missing ${file.name} after write/move');
    }
    _decode(bytes);
    if (!_sameBytes(bytes, expected)) {
      throw StateError('${file.name} differs from the intended snapshot');
    }
  }

  Future<void> _restore(DataFile file, List<int>? original) async {
    final current = await _storage.read(file);
    if (_sameBytes(current, original)) return;
    if (original == null) {
      await _storage.delete(file);
    } else {
      await _storage.writeTemp(original);
      if (!_sameBytes(await _storage.read(DataFile.temp), original)) {
        throw StateError('Rollback temp verification failed');
      }
      await _storage.move(DataFile.temp, file);
    }
    if (!_sameBytes(await _storage.read(file), original)) {
      throw StateError('Rollback ${file.name} verification failed');
    }
  }

  bool _sameBytes(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
