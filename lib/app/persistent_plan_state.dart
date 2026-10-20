import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backup/backup_import_result.dart';
import '../domain/car_validation.dart';
import '../domain/models/car.dart';
import '../domain/models/plan_conditions.dart';
import '../domain/models/year_month.dart';
import '../domain/plan_conditions_validation.dart';
import '../persistence/keep_my_car_data_mapper.dart';
import '../persistence/keep_my_car_repository.dart';
import '../persistence/keep_my_car_json_codec.dart';
import '../persistence/persistence_result.dart';
import '../photo/photo_library.dart';
import '../photo/photo_processor.dart';
import 'plan_session.dart';
import 'save_request.dart';

enum StartupPhase { loading, noData, ready, recovered, failure, uncertain }

typedef SessionFactory = PlanSession Function(
  RestoredCarData data,
  YearMonth referenceMonth,
);

class PhotoRequest {
  PhotoRequest._(this._owner, this._generation);
  final PersistentPlanState _owner;
  final int _generation;
  final _cancellation = PhotoCancellation();
  bool _started = false;
}

/// Owned once by the app. Candidates never mutate the formal session until save
/// succeeds. All reloads, including uncertainty recovery, use the same repository.
class PersistentPlanState extends ChangeNotifier {
  PersistentPlanState({
    required this.repository,
    required this.referenceMonth,
    SessionFactory? sessionFactory,
    this.photos,
  }) : _sessionFactory = sessionFactory ?? _newSession;

  final KeepMyCarRepository repository;
  final YearMonth referenceMonth;
  final SessionFactory _sessionFactory;
  final PhotoLibrary? photos;
  int _photoGeneration = 0;
  PhotoRequest? _photoRequest;
  Completer<void>? _idle;
  StartupPhase phase = StartupPhase.loading;
  PlanSession? session;
  Car? car;
  YearMonth? ownerBirthMonth;
  String? _photoId;
  String? get photoId => _photoId;
  bool _busy = false;
  bool _disposed = false;

  void _beginOperation() {
    _busy = true;
    _idle = Completer<void>();
  }

  void _endOperation() {
    _busy = false;
    _idle?.complete();
    _idle = null;
  }

  void cancelPhotoChange() {
    _photoGeneration++;
    _photoRequest?._cancellation.cancel();
    _photoRequest = null;
  }

  bool _validPhotoRequest(PhotoRequest request) =>
      identical(request._owner, this) &&
      identical(request, _photoRequest) &&
      request._generation == _photoGeneration &&
      !_disposed &&
      !request._cancellation.isCancelled &&
      !saveRestricted &&
      (phase == StartupPhase.ready || phase == StartupPhase.recovered);

  /// Start BEFORE any future picker wait. Selection UI is deliberately absent.
  PhotoRequest beginPhotoChange() {
    if (photos == null ||
        _disposed ||
        saveRestricted ||
        (phase != StartupPhase.ready && phase != StartupPhase.recovered)) {
      throw const SaveRequestFailure();
    }
    cancelPhotoChange();
    return _photoRequest = PhotoRequest._(this, _photoGeneration);
  }

  Future<bool> changePhoto(String sourcePath) =>
      completePhotoChange(beginPhotoChange(), sourcePath);

  /// false means superseded/cancelled. Failures never remove a candidate merely
  /// because Safe Save's API threw: the on-disk result may already reference it.
  Future<bool> completePhotoChange(
    PhotoRequest request,
    String sourcePath,
  ) async {
    if (!_validPhotoRequest(request) || request._started) return false;
    request._started = true;
    final library = photos!;
    final id = library.newId();
    PhotoLease? lease;
    try {
      // A returning selection must not be consumed by a transient cleanup busy.
      // Wait on the existing gate, then recheck generation/dispose/protection.
      while (_busy && _validPhotoRequest(request)) {
        await Future.any([_idle!.future, request._cancellation.cancelled]);
      }
      if (!_validPhotoRequest(request)) return false;
      lease = await library.acquireLease(
        id,
        cancellation: request._cancellation,
      );
      if (!_validPhotoRequest(request)) return false;
      await library.prepare(id, sourcePath, request._cancellation);
      while (_busy && _validPhotoRequest(request)) {
        await Future.any([_idle!.future, request._cancellation.cancelled]);
      }
      if (!_validPhotoRequest(request)) return false;
      // No await between reading the latest formal snapshot and taking _persist's
      // guard. Normal edits made during conversion are therefore retained.
      await _persist(_withPhoto(id), () {});
      return true;
    } on PhotoFailure catch (error) {
      if (error.issue == PhotoIssue.cancelled) return false;
      rethrow;
    } finally {
      lease?.release();
      await cleanupPhotos();
    }
  }

  RestoredCarData _withPhoto(String? id) {
    final latest = snapshot;
    return (
      photoId: id,
      ownerBirthMonth: latest.ownerBirthMonth,
      car: latest.car,
      planConditions: latest.planConditions,
      plannedExpenses: latest.plannedExpenses,
    );
  }

  Future<void> deletePhoto() async {
    if (_disposed ||
        saveRestricted ||
        _busy ||
        (phase != StartupPhase.ready && phase != StartupPhase.recovered)) {
      throw const SaveRequestFailure();
    }
    // Also invalidate a pending replacement when no photo is currently set.
    cancelPhotoChange();
    if (_photoId == null) return;
    await _persist(_withPhoto(null), () {});
  }

  Future<bool> _cleanupPhotoFiles() async {
    if (photos == null ||
        _disposed ||
        saveRestricted ||
        (phase != StartupPhase.ready && phase != StartupPhase.recovered)) {
      return false;
    }
    return repository.withPhotoReferencesForCleanup(photos!.cleanup);
  }

  Future<bool> cleanupPhotos() async {
    if (_busy) return false;
    _beginOperation();
    _notify();
    try {
      return await _cleanupPhotoFiles();
    } finally {
      _endOperation();
      _notify();
    }
  }

  VersionProtected? versionProtection;
  int? unsupportedBackupVersion;
  bool get saveRestricted =>
      versionProtection != null || unsupportedBackupVersion != null;

  bool get canRestoreBackup =>
      !_disposed &&
      !_busy &&
      !saveRestricted &&
      phase != StartupPhase.loading &&
      phase != StartupPhase.uncertain;

  bool get canExportBackup =>
      !_disposed &&
      !_busy &&
      versionProtection == null &&
      (phase == StartupPhase.ready || phase == StartupPhase.recovered);

  static PlanSession _newSession(RestoredCarData data, YearMonth reference) =>
      PlanSession(
        conditions: data.planConditions,
        birthMonth: data.ownerBirthMonth,
        referenceMonth: reference,
        firstRegistrationMonth: data.car.firstRegistrationMonth,
        plannedExpenses: data.plannedExpenses,
      );

  RestoredCarData get snapshot => (
    photoId: _photoId,
    ownerBirthMonth: ownerBirthMonth!,
    car: car!,
    planConditions: session!.conditions,
    plannedExpenses: session!.plannedExpenses,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _adopt(RestoredCarData data) {
    final nextSession = _sessionFactory(data, referenceMonth);
    ownerBirthMonth = data.ownerBirthMonth;
    _photoId = data.photoId;
    car = data.car;
    session = nextSession;
  }

  Future<void> load() async {
    if (_busy || _disposed) return;
    cancelPhotoChange();
    _beginOperation();
    phase = StartupPhase.loading;
    _notify();
    try {
      final result = await repository.load();
      if (_disposed) return;
      versionProtection = null;
      unsupportedBackupVersion = null;
      switch (result) {
        case Loaded(:final data, :final unsupportedBackupVersion):
          this.unsupportedBackupVersion = unsupportedBackupVersion;
          _adopt(data);
          phase = StartupPhase.ready;
        case Recovered(:final data):
          _adopt(data);
          phase = StartupPhase.recovered;
        case NoData():
          _photoId = null;
          car = null;
          session = null;
          ownerBirthMonth = null;
          phase = StartupPhase.noData;
        case VersionProtected():
          _photoId = null;
          // E-2 uses this typed protection to replace the legacy failure UI.
          // Destructive boundaries already reject operations in E-1.
          versionProtection = result;
          session = null;
          car = null;
          ownerBirthMonth = null;
          phase = StartupPhase.failure;
        case LoadFailure():
          phase = StartupPhase.failure;
      }
    } catch (_) {
      phase = StartupPhase.failure;
    } finally {
      _endOperation();
      _notify();
    }
  }

  void acknowledgeRecovery() {
    if (phase == StartupPhase.recovered) {
      phase = StartupPhase.ready;
      _notify();
    }
  }

  Future<void> _persist(
    RestoredCarData candidate,
    VoidCallback commit, {
    bool restoringBackup = false,
    VoidCallback? prepare,
  }) async {
    if (_disposed ||
        saveRestricted ||
        _busy ||
        phase == StartupPhase.loading ||
        (phase == StartupPhase.failure && !restoringBackup) ||
        phase == StartupPhase.uncertain) {
      throw const SaveRequestFailure();
    }
    _beginOperation();
    try {
      prepare?.call();
      final result = await repository.save(candidate);
      if (_disposed) throw const SaveRequestFailure();
      if (result is SaveFailure) {
        if (result.issue.cause case UnsupportedStorageVersion(
          :final version,
          :final file,
        )) {
          if (file == 'backup') {
            unsupportedBackupVersion = version;
          } else {
            versionProtection = VersionProtected(
              file: file ?? 'current',
              version: version,
            );
          }
          _notify();
        }
        if (result.rollbackIssues.isNotEmpty) {
          phase = StartupPhase.uncertain;
          _notify();
          throw const SaveRequestFailure(uncertain: true);
        }
        throw const SaveRequestFailure();
      }
      commit();
      _photoId = candidate.photoId;
      _notify();
      await _cleanupPhotoFiles();
    } finally {
      _endOperation();
      // Saved is announced before cleanup; also announce that the cleanup/save
      // gate is open again so computed Import/Export availability is refreshed.
      if (photos != null) _notify();
    }
  }

  /// Accepts the fully validated 14-A2 result. Preparation is detached from the
  /// formal state; after Safe Save only non-throwing field assignments remain.
  Future<void> restoreFromBackup(BackupImportSuccess backup) async {
    try {
      final data = backup.data;
      final RestoredCarData candidate = (
        // External JSON backups replace the whole plan and contain no photo.
        photoId: null,
        ownerBirthMonth: data.ownerBirthMonth,
        car: data.car,
        planConditions: data.planConditions,
        plannedExpenses: List.unmodifiable(data.plannedExpenses),
      );
      late final PlanSession nextSession;
      await _persist(
        candidate,
        () {
          ownerBirthMonth = candidate.ownerBirthMonth;
          car = candidate.car;
          session = nextSession;
          phase = StartupPhase.ready;
        },
        restoringBackup: true,
        prepare: () {
          cancelPhotoChange();
          nextSession = _sessionFactory(candidate, referenceMonth);
        },
      );
    } on SaveRequestFailure {
      rethrow;
    } catch (_) {
      throw const SaveRequestFailure();
    }
  }

  Future<void> initialize(RestoredCarData candidate) async {
    if (phase != StartupPhase.noData ||
        candidate.plannedExpenses.isNotEmpty ||
        candidate.photoId != null) {
      throw const SaveRequestFailure();
    }
    final errors =
        (candidate.planConditions.fundingPlanEnabled
        ? validatePlanConditions
        : validateBasicPlanConditions)(
          candidate.planConditions,
          birthMonth: candidate.ownerBirthMonth,
          referenceMonth: referenceMonth,
        );
    if (errors.isNotEmpty ||
        validateCarName(candidate.car.name).error != null) {
      throw const SaveRequestFailure();
    }
    await _persist(candidate, () {
      _adopt(candidate);
      phase = StartupPhase.ready;
    });
  }

  Future<void> discardFailureAndStartNew() async {
    if (_disposed || saveRestricted || _busy || phase != StartupPhase.failure) {
      throw const SaveRequestFailure();
    }
    cancelPhotoChange();
    _beginOperation();
    try {
      final result = await repository.discardUnreadableData();
      if (_disposed) throw const SaveRequestFailure();
      if (result is SaveFailure) {
        if (result.rollbackIssues.isNotEmpty) {
          phase = StartupPhase.uncertain;
          _notify();
          throw const SaveRequestFailure(uncertain: true);
        }
        throw const SaveRequestFailure();
      }
      car = null;
      _photoId = null;
      session = null;
      ownerBirthMonth = null;
      phase = StartupPhase.noData;
      _notify();
    } on SaveRequestFailure {
      rethrow;
    } catch (_) {
      throw const SaveRequestFailure();
    } finally {
      _endOperation();
    }
  }

  FutureOr<CarNameError?> saveCarName(String input) {
    final result = validateCarName(input);
    if (result.error != null) return result.error;
    if (result.name == car!.name) return null;
    final candidate = car!.copyWith(name: result.name);
    return _persist((
      photoId: _photoId,
      ownerBirthMonth: ownerBirthMonth!,
      car: candidate,
      planConditions: session!.conditions,
      plannedExpenses: session!.plannedExpenses,
    ), () => car = candidate).then((_) => null);
  }

  FutureOr<Map<PlanField, PlanInputError>> applyBasic(PlanConditions input) {
    final next = basicPlanCandidate(input, session!.conditions);
    return _applyConditions(
      next,
      validateBasicPlanConditions(
        next,
        birthMonth: ownerBirthMonth!,
        referenceMonth: referenceMonth,
      ),
    );
  }

  FutureOr<Map<PlanField, PlanInputError>> applyFunding(PlanConditions input) {
    final next = fundingPlanCandidate(input, session!.conditions);
    return _applyConditions(
      next,
      next.fundingPlanEnabled
          ? validateFundingPlanConditions(
              next,
              birthMonth: ownerBirthMonth!,
              referenceMonth: referenceMonth,
            )
          : <PlanField, PlanInputError>{},
    );
  }

  FutureOr<Map<PlanField, PlanInputError>> apply(PlanConditions next) {
    final errors = validatePlanConditions(
      next,
      birthMonth: ownerBirthMonth!,
      referenceMonth: referenceMonth,
    );
    return _applyConditions(next, errors);
  }

  FutureOr<Map<PlanField, PlanInputError>> _applyConditions(
    PlanConditions next,
    Map<PlanField, PlanInputError> errors,
  ) {
    if (errors.isNotEmpty || next == session!.conditions) return errors;
    final candidateCar = car!.copyWith(
      currentMileageKm: next.currentMileageKm,
      annualMileageKm: next.annualMileageKm,
    );
    return _persist(
      (
        photoId: _photoId,
        ownerBirthMonth: ownerBirthMonth!,
        car: candidateCar,
        planConditions: next,
        plannedExpenses: session!.plannedExpenses,
      ),
      () {
        session!.adoptValidatedConditions(next);
        car = candidateCar;
      },
    ).then((_) => <PlanField, PlanInputError>{});
  }

  Future<ExpenseChange> saveExpense({
    int? id,
    required String name,
    required YearMonth month,
    required int amountYen,
  }) async {
    final candidate = session!.prepareExpense(
      id: id,
      name: name,
      month: month,
      amountYen: amountYen,
    );
    if (candidate.change == ExpenseChange.unchanged) return candidate.change;
    await _persist(
      (
        photoId: _photoId,
        ownerBirthMonth: ownerBirthMonth!,
        car: car!,
        planConditions: session!.conditions,
        plannedExpenses: candidate.expenses,
      ),
      () {
        session!.adoptValidatedExpenses(candidate);
      },
    );
    return candidate.change;
  }

  Future<ExpenseChange> deleteExpense(int id) async {
    final candidate = session!.prepareExpenseDeletion(id);
    if (candidate.change == ExpenseChange.unchanged) {
      return ExpenseChange.unchanged;
    }
    await _persist((
      photoId: _photoId,
      ownerBirthMonth: ownerBirthMonth!,
      car: car!,
      planConditions: session!.conditions,
      plannedExpenses: candidate.expenses,
    ), () => session!.adoptValidatedExpenses(candidate));
    return ExpenseChange.deleted;
  }

  @override
  void dispose() {
    cancelPhotoChange();
    _disposed = true;
    super.dispose();
  }
}
