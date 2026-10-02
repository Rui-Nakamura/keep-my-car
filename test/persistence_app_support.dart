import 'dart:async';

import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import 'plan_test_support.dart' as support;

class TestRepository extends KeepMyCarRepository {
  TestRepository(this.result)
    : super(
        IoLocalFileStorage(
          directory: () =>
              throw StateError('Test must not access application files'),
        ),
      );
  LoadResult result;
  SaveResult saveResult = const Saved();
  Future<LoadResult> Function()? onLoad;
  Future<SaveResult> Function(RestoredCarData)? onSave;
  int loads = 0;
  int discards = 0;
  SaveResult discardResult = const Saved();
  @override
  Future<SaveResult> discardUnreadableData() async {
    discards++;
    if (discardResult is Saved) result = const NoData();
    return discardResult;
  }

  final saves = <RestoredCarData>[];
  @override
  Future<LoadResult> load() async {
    loads++;
    return onLoad == null ? result : await onLoad!();
  }

  @override
  Future<SaveResult> save(RestoredCarData snapshot) async {
    saves.add(snapshot);
    final saved = onSave == null ? saveResult : await onSave!(snapshot);
    if (saved is Saved) result = Loaded(snapshot);
    return saved;
  }
}

RestoredCarData sampleSnapshot([PlanSession? plan]) {
  final p = plan ?? support.session();
  return (
    ownerBirthMonth: p.birthMonth,
    car: goldenSample.car.copyWith(
      currentMileageKm: p.conditions.currentMileageKm,
      annualMileageKm: p.conditions.annualMileageKm,
    ),
    planConditions: p.conditions,
    plannedExpenses: p.plannedExpenses,
  );
}

/// Existing visual/regression tests explicitly load their development fixture.
KeepMyCarApp testApp({PlanSession? session}) {
  final plan = session ?? support.session();
  return KeepMyCarApp(
    repository: TestRepository(Loaded(sampleSnapshot(plan))),
    now: () => DateTime(plan.referenceMonth.year, plan.referenceMonth.month),
    sessionFactory: (_, _) => plan,
  );
}

SaveFailure saveFailure({bool uncertain = false}) => SaveFailure(
  PersistenceIssue(
    PersistenceStage.writeTemp,
    StateError('test save failure'),
    StackTrace.current,
  ),
  rollbackIssues: uncertain
      ? [
          PersistenceIssue(
            PersistenceStage.rollback,
            StateError('test rollback failure'),
            StackTrace.current,
          ),
        ]
      : [],
);
