import '../domain/models/plan_conditions.dart';
import '../domain/models/planned_expense.dart';
import '../domain/models/year_month.dart';
import '../domain/plan_conditions_validation.dart';
import '../domain/planned_expense_validation.dart';
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

enum ExpenseChange { added, updated, deleted, unchanged }

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
  }) : _plannedExpenses = List.unmodifiable(plannedExpenses) {
    final ids = <int>{};
    for (final expense in plannedExpenses) {
      if (!ids.add(expense.id)) throw ArgumentError('Duplicate expense ID');
      if (expense.id >= _nextExpenseId) _nextExpenseId = expense.id + 1;
    }
    _timeline = _calculateTimeline();
    _reserveResult = _calculateReserve();
  }

  final YearMonth birthMonth;
  final YearMonth referenceMonth;
  final YearMonth firstRegistrationMonth;
  List<PlannedExpense> _plannedExpenses;
  int _nextExpenseId = 1;
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
  List<PlannedExpense> get plannedExpenses => _plannedExpenses;
  YearMonth get ownershipTargetMonth =>
      reserveMonth(birthMonth, _conditions.ownershipTargetAge);
  bool isExpenseIncluded(PlannedExpense expense) => isExpenseMonthInRange(
    expense.plannedMonth,
    referenceMonth: referenceMonth,
    ownershipTargetMonth: ownershipTargetMonth,
  );
  List<PlannedExpense> get includedExpenses =>
      List.unmodifiable(plannedExpenses.where(isExpenseIncluded));

  ExpenseChange saveExpense({
    int? id,
    required String name,
    required YearMonth month,
    required int amountYen,
  }) {
    final errors = validatePlannedExpense(
      name: name,
      month: month,
      amount: '$amountYen',
      referenceMonth: referenceMonth,
      ownershipTargetMonth: ownershipTargetMonth,
    );
    if (errors.isNotEmpty) throw ArgumentError.value(errors, 'expense');
    final index = id == null
        ? -1
        : plannedExpenses.indexWhere((e) => e.id == id);
    if (id != null && index < 0) throw ArgumentError.value(id, 'id');
    final old = index < 0 ? null : plannedExpenses[index];
    final normalized = name.trim();
    if (old != null &&
        old.name == normalized &&
        old.plannedMonth == month &&
        old.amountYen == amountYen) {
      return ExpenseChange.unchanged;
    }
    final expense = PlannedExpense(
      id: old?.id ?? _nextExpenseId++,
      name: normalized,
      plannedMonth: month,
      amountYen: amountYen,
      basis: old?.basis ?? ExpenseBasis.placeholder,
      status: old?.status ?? PlannedExpenseStatus.planned,
      memo: old?.memo,
    );
    final next = plannedExpenses.toList();
    if (old == null) {
      next.add(expense);
    } else {
      next[index] = expense;
    }
    _plannedExpenses = List.unmodifiable(next);
    _recalculate(timelineAffected: true, reserveAffected: true);
    return old == null ? ExpenseChange.added : ExpenseChange.updated;
  }

  ExpenseChange deleteExpense(int id) {
    final index = plannedExpenses.indexWhere((e) => e.id == id);
    if (index < 0) return ExpenseChange.unchanged;
    _plannedExpenses = List.unmodifiable(
      plannedExpenses.toList()..removeAt(index),
    );
    _recalculate(timelineAffected: true, reserveAffected: true);
    return ExpenseChange.deleted;
  }

  Map<PlanField, PlanInputError> apply(PlanConditions next) {
    final errors = validatePlanConditions(
      next,
      birthMonth: birthMonth,
      referenceMonth: referenceMonth,
    );
    if (errors.isNotEmpty || next == _conditions) return errors;
    final old = _conditions;
    final oldIncluded = includedExpenses;
    _conditions = next;
    final expensesAffected = !_sameExpenses(oldIncluded, includedExpenses);
    final timelineAffected =
        expensesAffected ||
        next.currentMileageKm != old.currentMileageKm ||
        next.annualMileageKm != old.annualMileageKm;
    final reserveAffected =
        expensesAffected ||
        next.currentCarFundYen != old.currentCarFundYen ||
        next.reserveTargetAge != old.reserveTargetAge ||
        next.largeRepairReserveYen != old.largeRepairReserveYen;
    _recalculate(
      timelineAffected: timelineAffected,
      reserveAffected: reserveAffected,
    );
    return errors;
  }

  void _recalculate({
    required bool timelineAffected,
    required bool reserveAffected,
  }) {
    var timelineChanged = false;
    var reserveChanged = false;
    if (timelineAffected) {
      final result = _calculateTimeline();
      timelineChanged = result.length != _timeline.length;
      for (var i = 0; !timelineChanged && i < result.length; i++) {
        final a = result[i];
        final b = _timeline[i];
        timelineChanged =
            a.year != b.year ||
            a.ownerAge != b.ownerAge ||
            a.carAge != b.carAge ||
            a.mileageKm != b.mileageKm ||
            a.isCurrent != b.isCurrent ||
            a.totalYen != b.totalYen ||
            !_sameExpenses(a.expenses, b.expenses);
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
  }

  // Compare displayed values as well as amounts: names, months and zero-cost
  // rows are part of the formal timeline result.
  bool _sameExpenses(List<PlannedExpense> a, List<PlannedExpense> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].plannedMonth != b[i].plannedMonth ||
          a[i].amountYen != b[i].amountYen) {
        return false;
      }
    }
    return true;
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
      plannedExpenses: includedExpenses,
    ),
  );

  RepairReserveCalculationResult _calculateReserve() => _reserveCalculator(
    referenceMonth: referenceMonth,
    currentCarFundYen: _conditions.currentCarFundYen,
    reserveTargetMonth: reserveMonth(birthMonth, _conditions.reserveTargetAge),
    largeRepairReserveYen: _conditions.largeRepairReserveYen,
    plannedExpenses: includedExpenses,
  );
}
