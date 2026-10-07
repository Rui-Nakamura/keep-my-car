import '../../domain/models/planned_expense.dart';
import '../../domain/models/year_month.dart';
import '../../domain/plan_conditions_validation.dart';
import '../../domain/projected_mileage.dart';
import '../../domain/planned_expense_validation.dart';

/// Calculated year rows through the ownership target, independent of widgets.
class TimelineYearData {
  TimelineYearData({
    required this.year,
    required this.ownerAge,
    required this.carAge,
    required this.mileageKm,
    required this.isCurrent,
    required List<PlannedExpense> expenses,
    required this.totalYen,
  }) : expenses = List.unmodifiable(expenses);

  final int year;
  final int ownerAge;
  final int carAge;
  final int mileageKm;
  final bool isCurrent;
  final List<PlannedExpense> expenses;
  final int totalYen;
}

typedef TimelineCalculator = List<TimelineYearData> Function({
  required YearMonth referenceMonth,
  required YearMonth birthMonth,
  required YearMonth firstRegistrationMonth,
  required YearMonth ownershipTargetMonth,
  required int currentMileageKm,
  required int annualMileageKm,
  required List<PlannedExpense> plannedExpenses,
});

List<TimelineYearData> calculateFutureTimeline({
  required YearMonth referenceMonth,
  required YearMonth birthMonth,
  required YearMonth firstRegistrationMonth,
  required YearMonth ownershipTargetMonth,
  required int currentMileageKm,
  required int annualMileageKm,
  required List<PlannedExpense> plannedExpenses,
}) {
  final currentYear = referenceMonth.year;
  final currentOwnerAge = completedYears(birthMonth, referenceMonth);
  final currentCarAge = completedYears(firstRegistrationMonth, referenceMonth);
  final lastYear = ownershipTargetMonth.year < currentYear
      ? currentYear
      : ownershipTargetMonth.year;
  final sorted =
      plannedExpenses.indexed
          .where(
            (entry) => isExpenseMonthInRange(
              entry.$2.plannedMonth,
              referenceMonth: referenceMonth,
              ownershipTargetMonth: ownershipTargetMonth,
            ),
          )
          .toList()
        ..sort((a, b) {
          final order = a.$2.plannedMonth.compareTo(b.$2.plannedMonth);
          return order != 0 ? order : a.$1.compareTo(b.$1);
        });
  final expensesByYear = <int, List<PlannedExpense>>{};
  for (final entry in sorted) {
    (expensesByYear[entry.$2.plannedMonth.year] ??= []).add(entry.$2);
  }
  return List.unmodifiable(
    List.generate(lastYear - currentYear + 1, (offset) {
      final useTargetMonth =
          currentYear + offset == ownershipTargetMonth.year &&
          ownershipTargetMonth.compareTo(referenceMonth) >= 0;
      final expenses =
          expensesByYear[currentYear + offset] ?? <PlannedExpense>[];
      return TimelineYearData(
        year: currentYear + offset,
        ownerAge: useTargetMonth
            ? completedYears(birthMonth, ownershipTargetMonth)
            : currentOwnerAge + offset,
        carAge: useTargetMonth
            ? completedYears(firstRegistrationMonth, ownershipTargetMonth)
            : currentCarAge + offset,
        mileageKm: projectedMileageKm(
          currentMileageKm: currentMileageKm,
          annualMileageKm: annualMileageKm,
          referenceMonth: referenceMonth,
          targetMonth: useTargetMonth
              ? ownershipTargetMonth
              : YearMonth(currentYear + offset, referenceMonth.month),
        ),
        isCurrent: offset == 0,
        expenses: expenses,
        totalYen: expenses.fold<int>(
          0,
          (sum, expense) => sum + expense.amountYen,
        ),
      );
    }),
  );
}
