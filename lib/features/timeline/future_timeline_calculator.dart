import '../../domain/models/planned_expense.dart';

/// Presentation data for the existing ten-year timeline, not a planning engine.
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
  required int currentYear,
  required int currentOwnerAge,
  required int currentCarAge,
  required int currentMileageKm,
  required int annualMileageKm,
  required List<PlannedExpense> plannedExpenses,
});

List<TimelineYearData> calculateFutureTimeline({
  required int currentYear,
  required int currentOwnerAge,
  required int currentCarAge,
  required int currentMileageKm,
  required int annualMileageKm,
  required List<PlannedExpense> plannedExpenses,
}) {
  final sorted =
      plannedExpenses.indexed.where((entry) {
        final year = entry.$2.plannedMonth.year;
        return year >= currentYear && year < currentYear + 10;
      }).toList()..sort((a, b) {
        final order = a.$2.plannedMonth.compareTo(b.$2.plannedMonth);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
  final expensesByYear = <int, List<PlannedExpense>>{};
  for (final entry in sorted) {
    (expensesByYear[entry.$2.plannedMonth.year] ??= []).add(entry.$2);
  }
  return List.unmodifiable(
    List.generate(10, (offset) {
      final expenses =
          expensesByYear[currentYear + offset] ?? <PlannedExpense>[];
      return TimelineYearData(
        year: currentYear + offset,
        ownerAge: currentOwnerAge + offset,
        carAge: currentCarAge + offset,
        mileageKm: currentMileageKm + annualMileageKm * offset,
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
