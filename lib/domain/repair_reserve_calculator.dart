import 'models/planned_expense.dart';
import 'models/year_month.dart';

sealed class RepairReserveCalculationResult {
  const RepairReserveCalculationResult();
}

final class RepairReserveSuccess extends RepairReserveCalculationResult {
  const RepairReserveSuccess({
    required this.plannedExpensesOnlyMonthlyYen,
    required this.repairIncludedMonthlyYen,
    required this.additionalMonthlyYen,
  });

  final int plannedExpensesOnlyMonthlyYen;
  final int repairIncludedMonthlyYen;
  final int additionalMonthlyYen;
}

enum RepairReserveError { invalidInput, inconsistentResult }

final class RepairReserveFailure extends RepairReserveCalculationResult {
  const RepairReserveFailure(this.error);

  final RepairReserveError error;
}

RepairReserveCalculationResult calculateRepairReserve({
  required YearMonth referenceMonth,
  required int currentCarFundYen,
  required YearMonth reserveTargetMonth,
  required int largeRepairReserveYen,
  required List<PlannedExpense> plannedExpenses,
}) {
  // Validate the whole input before filtering out-of-period expenses.
  if (currentCarFundYen < 0 ||
      largeRepairReserveYen < 0 ||
      reserveTargetMonth.compareTo(referenceMonth) < 0 ||
      plannedExpenses.any((expense) => expense.amountYen < 0)) {
    return const RepairReserveFailure(RepairReserveError.invalidInput);
  }

  final monthCount = _monthsFrom(referenceMonth, reserveTargetMonth) + 1;
  final expensesByMonth = <int, int>{};
  for (final expense in plannedExpenses) {
    final month = _monthsFrom(referenceMonth, expense.plannedMonth) + 1;
    if (month >= 1 && month <= monthCount) {
      expensesByMonth.update(
        month,
        (amount) => amount + expense.amountYen,
        ifAbsent: () => expense.amountYen,
      );
    }
  }

  int requiredMonthly(int targetBalance) {
    var cumulativeExpenses = 0;
    var required = 0;
    for (var month = 1; month <= monthCount; month++) {
      cumulativeExpenses += expensesByMonth[month] ?? 0;
      final balance = month == monthCount ? targetBalance : 0;
      final shortfall = cumulativeExpenses + balance - currentCarFundYen;
      if (shortfall > 0) {
        // Positive integer ceiling, without floating-point money arithmetic.
        final monthly = shortfall ~/ month + (shortfall % month == 0 ? 0 : 1);
        if (monthly > required) required = monthly;
      }
    }
    return required;
  }

  final plannedOnly = requiredMonthly(0);
  final repairIncluded = requiredMonthly(largeRepairReserveYen);
  final additional = repairIncluded - plannedOnly;
  if (additional < 0) {
    return const RepairReserveFailure(RepairReserveError.inconsistentResult);
  }
  return RepairReserveSuccess(
    plannedExpensesOnlyMonthlyYen: plannedOnly,
    repairIncludedMonthlyYen: repairIncluded,
    additionalMonthlyYen: additional,
  );
}

int _monthsFrom(YearMonth start, YearMonth end) =>
    (end.year - start.year) * 12 + end.month - start.month;
