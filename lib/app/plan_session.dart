import '../domain/models/plan_conditions.dart';
import '../domain/models/planned_expense.dart';
import '../domain/models/year_month.dart';
import '../domain/plan_conditions_validation.dart';
import '../domain/repair_reserve_calculator.dart';
import '../features/timeline/future_timeline_calculator.dart';

typedef ReserveCalculator = RepairReserveCalculationResult Function({
  required YearMonth referenceMonth,
  required int currentCarFundYen,
  required YearMonth reserveTargetMonth,
  required int largeRepairReserveYen,
  required List<PlannedExpense> plannedExpenses,
});

enum HomeUpdate { timeline, reserve, both }

/// One in-memory session owned by the app. No widgets, navigation or storage.
class PlanSession {
  PlanSession({
    required this._conditions,
    required this.birthMonth,
    required this.referenceMonth,
    required this.firstRegistrationMonth,
    required List<PlannedExpense> plannedExpenses,
    this._timelineCalculator = calculateFutureTimeline,
    this._reserveCalculator = calculateRepairReserve,
  }) : plannedExpenses = List.unmodifiable(plannedExpenses) {
    _timeline = _calculateTimeline();
    _reserveResult = _calculateReserve();
  }

  final YearMonth birthMonth;
  final YearMonth referenceMonth;
  final YearMonth firstRegistrationMonth;
  final List<PlannedExpense> plannedExpenses;
  final TimelineCalculator _timelineCalculator;
  final ReserveCalculator _reserveCalculator;
  PlanConditions _conditions;
  late List<TimelineYearData> _timeline;
  late RepairReserveCalculationResult _reserveResult;
  bool _timelinePending = false;
  bool _reservePending = false;
  int? _reserveDeltaYen;
  HomeUpdate? _homeUpdate;

  PlanConditions get conditions => _conditions;
  List<TimelineYearData> get timeline => _timeline;
  RepairReserveCalculationResult get reserveResult => _reserveResult;
  bool get timelinePending => _timelinePending;
  bool get reservePending => _reservePending;
  int? get reserveDeltaYen => _reserveDeltaYen;
  HomeUpdate? get homeUpdate => _homeUpdate;

  Map<PlanField, PlanInputError> apply(PlanConditions next) {
    final errors = validatePlanConditions(
      next,
      birthMonth: birthMonth,
      referenceMonth: referenceMonth,
    );
    if (errors.isNotEmpty || next == _conditions) return errors;
    final old = _conditions;
    final timelineAffected =
        next.currentMileageKm != old.currentMileageKm ||
        next.annualMileageKm != old.annualMileageKm;
    final reserveAffected =
        next.currentCarFundYen != old.currentCarFundYen ||
        next.reserveTargetAge != old.reserveTargetAge ||
        next.largeRepairReserveYen != old.largeRepairReserveYen;
    _conditions = next;
    var timelineChanged = false;
    var reserveChanged = false;
    if (timelineAffected) {
      final result = _calculateTimeline();
      timelineChanged = result.length != _timeline.length;
      for (var i = 0; !timelineChanged && i < result.length; i++) {
        timelineChanged = result[i].mileageKm != _timeline[i].mileageKm;
      }
      _timeline = result;
      if (timelineChanged) _timelinePending = true;
    }
    if (reserveAffected) {
      final previous = _reserveResult;
      final result = _calculateReserve();
      if (previous is RepairReserveSuccess && result is RepairReserveSuccess) {
        reserveChanged =
            previous.plannedExpensesOnlyMonthlyYen !=
                result.plannedExpensesOnlyMonthlyYen ||
            previous.repairIncludedMonthlyYen !=
                result.repairIncludedMonthlyYen ||
            previous.additionalMonthlyYen != result.additionalMonthlyYen;
        if (reserveChanged) {
          _reservePending = true;
          _reserveDeltaYen =
              result.repairIncludedMonthlyYen -
              previous.repairIncludedMonthlyYen;
        }
      } else {
        // No monetary comparison is defined across a failed calculation.
        _reservePending = false;
        _reserveDeltaYen = null;
      }
      _reserveResult = result;
    }
    _homeUpdate = timelineChanged && reserveChanged
        ? HomeUpdate.both
        : timelineChanged
        ? HomeUpdate.timeline
        : reserveChanged
        ? HomeUpdate.reserve
        : null;
    return errors;
  }

  void acknowledgeTimeline() {
    _timelinePending = false;
  }

  void acknowledgeReserve() {
    _reservePending = false;
    _reserveDeltaYen = null;
  }

  void consumeHomeUpdate() {
    _homeUpdate = null;
  }

  List<TimelineYearData> _calculateTimeline() => List.unmodifiable(
    _timelineCalculator(
      currentYear: referenceMonth.year,
      currentOwnerAge: completedYears(birthMonth, referenceMonth),
      currentCarAge: completedYears(firstRegistrationMonth, referenceMonth),
      currentMileageKm: _conditions.currentMileageKm,
      annualMileageKm: _conditions.annualMileageKm,
      plannedExpenses: plannedExpenses,
    ),
  );

  RepairReserveCalculationResult _calculateReserve() => _reserveCalculator(
    referenceMonth: referenceMonth,
    currentCarFundYen: _conditions.currentCarFundYen,
    reserveTargetMonth: reserveMonth(birthMonth, _conditions.reserveTargetAge),
    largeRepairReserveYen: _conditions.largeRepairReserveYen,
    plannedExpenses: plannedExpenses,
  );
}
