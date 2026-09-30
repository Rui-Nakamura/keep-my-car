import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/car_validation.dart';
import '../domain/models/car.dart';
import '../domain/models/plan_conditions.dart';
import '../domain/models/year_month.dart';
import '../domain/plan_conditions_validation.dart';
import '../persistence/keep_my_car_data_mapper.dart';
import '../persistence/keep_my_car_repository.dart';
import '../persistence/persistence_result.dart';
import 'plan_session.dart';
import 'save_request.dart';

enum StartupPhase { loading, noData, ready, recovered, failure, uncertain }

typedef SessionFactory = PlanSession Function(
  RestoredCarData data,
  YearMonth referenceMonth,
);

/// Owned once by the app. Candidates never mutate the formal session until save
/// succeeds. All reloads, including uncertainty recovery, use the same repository.
class PersistentPlanState extends ChangeNotifier {
  PersistentPlanState({
    required this.repository,
    required this.referenceMonth,
    SessionFactory? sessionFactory,
  }) : _sessionFactory = sessionFactory ?? _newSession;

  final KeepMyCarRepository repository;
  final YearMonth referenceMonth;
  final SessionFactory _sessionFactory;
  StartupPhase phase = StartupPhase.loading;
  PlanSession? session;
  Car? car;
  YearMonth? ownerBirthMonth;
  bool _busy = false;
  bool _disposed = false;

  static PlanSession _newSession(RestoredCarData data, YearMonth reference) =>
      PlanSession(
        conditions: data.planConditions,
        birthMonth: data.ownerBirthMonth,
        referenceMonth: reference,
        firstRegistrationMonth: data.car.firstRegistrationMonth,
        plannedExpenses: data.plannedExpenses,
      );

  RestoredCarData get snapshot => (
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
    car = data.car;
    session = nextSession;
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    phase = StartupPhase.loading;
    _notify();
    try {
      final result = await repository.load();
      if (_disposed) return;
      switch (result) {
        case Loaded(:final data):
          _adopt(data);
          phase = StartupPhase.ready;
        case Recovered(:final data):
          _adopt(data);
          phase = StartupPhase.recovered;
        case NoData():
          car = null;
          session = null;
          ownerBirthMonth = null;
          phase = StartupPhase.noData;
        case LoadFailure():
          phase = StartupPhase.failure;
      }
    } catch (_) {
      phase = StartupPhase.failure;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void acknowledgeRecovery() {
    if (phase == StartupPhase.recovered) {
      phase = StartupPhase.ready;
      _notify();
    }
  }

  Future<void> _persist(RestoredCarData candidate, VoidCallback commit) async {
    if (_busy ||
        phase == StartupPhase.loading ||
        phase == StartupPhase.failure ||
        phase == StartupPhase.uncertain) {
      throw const SaveRequestFailure();
    }
    _busy = true;
    try {
      final result = await repository.save(candidate);
      if (_disposed) throw const SaveRequestFailure();
      if (result is SaveFailure) {
        if (result.rollbackIssues.isNotEmpty) {
          phase = StartupPhase.uncertain;
          _notify();
          throw const SaveRequestFailure(uncertain: true);
        }
        throw const SaveRequestFailure();
      }
      commit();
      _notify();
    } finally {
      _busy = false;
    }
  }

  Future<void> initialize(RestoredCarData candidate) async {
    if (phase != StartupPhase.noData || candidate.plannedExpenses.isNotEmpty) {
      throw const SaveRequestFailure();
    }
    final errors = validatePlanConditions(
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

  FutureOr<CarNameError?> saveCarName(String input) {
    final result = validateCarName(input);
    if (result.error != null) return result.error;
    if (result.name == car!.name) return null;
    final candidate = car!.copyWith(name: result.name);
    return _persist((
      ownerBirthMonth: ownerBirthMonth!,
      car: candidate,
      planConditions: session!.conditions,
      plannedExpenses: session!.plannedExpenses,
    ), () => car = candidate).then((_) => null);
  }

  FutureOr<Map<PlanField, PlanInputError>> apply(PlanConditions next) {
    final errors = validatePlanConditions(
      next,
      birthMonth: ownerBirthMonth!,
      referenceMonth: referenceMonth,
    );
    if (errors.isNotEmpty || next == session!.conditions) return errors;
    final candidateCar = car!.copyWith(
      currentMileageKm: next.currentMileageKm,
      annualMileageKm: next.annualMileageKm,
    );
    return _persist(
      (
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
      ownerBirthMonth: ownerBirthMonth!,
      car: car!,
      planConditions: session!.conditions,
      plannedExpenses: candidate.expenses,
    ), () => session!.adoptValidatedExpenses(candidate));
    return ExpenseChange.deleted;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
