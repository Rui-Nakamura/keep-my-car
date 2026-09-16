import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

PlannedExpense expense(int month, int amount, {int year = 2026}) =>
    PlannedExpense(
      name: '予定費',
      plannedMonth: YearMonth(year, month),
      amountYen: amount,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );

RepairReserveCalculationResult calculate({
  int fund = 0,
  int reserve = 0,
  YearMonth target = const YearMonth(2026, 11),
  List<PlannedExpense> expenses = const [],
}) => calculateRepairReserve(
  referenceMonth: const YearMonth(2026, 9),
  currentCarFundYen: fund,
  reserveTargetMonth: target,
  largeRepairReserveYen: reserve,
  plannedExpenses: expenses,
);

void expectAmounts(
  RepairReserveCalculationResult result,
  int planned,
  int included,
  int additional,
) {
  expect(result, isA<RepairReserveSuccess>());
  final success = result as RepairReserveSuccess;
  expect(success.plannedExpensesOnlyMonthlyYen, planned);
  expect(success.repairIncludedMonthlyYen, included);
  expect(success.additionalMonthlyYen, additional);
  expect(
    success.additionalMonthlyYen,
    success.repairIncludedMonthlyYen - success.plannedExpensesOnlyMonthlyYen,
  );
}

void main() {
  test(
    'Golden Sample: intermediate constraint and 104-month reserve target',
    () {
      final result = calculateRepairReserve(
        referenceMonth: goldenSample.referenceMonth,
        currentCarFundYen: goldenSample.currentCarFundYen,
        reserveTargetMonth: const YearMonth(2035, 4),
        largeRepairReserveYen: goldenSample.reserve.amountYen,
        plannedExpenses: goldenSample.plannedExpenses,
      );
      // Planned-only binds at month 97; reserve binds at month 104.
      expectAmounts(result, 11341, 29808, 18467);
    },
  );

  test('reference month expenses require funds in the first month', () {
    expectAmounts(calculate(expenses: [expense(9, 100)]), 100, 100, 0);
  });

  test('target month includes both its expense and its contribution', () {
    expectAmounts(
      calculate(reserve: 60, expenses: [expense(11, 90)]),
      30,
      50,
      20,
    );
  });

  test('expenses before reference month are excluded', () {
    expectAmounts(calculate(expenses: [expense(8, 900)]), 0, 0, 0);
  });

  test('expenses after target month are excluded', () {
    expectAmounts(calculate(expenses: [expense(12, 900)]), 0, 0, 0);
  });

  test('all same-month expenses including duplicates are summed', () {
    expectAmounts(
      calculate(expenses: [expense(10, 40), expense(10, 40), expense(10, 20)]),
      50,
      50,
      0,
    );
  });

  test(
    'early shortfall dominates final target; additional is not reserve/N',
    () {
      expectAmounts(
        calculate(reserve: 60, expenses: [expense(9, 90)]),
        90,
        90,
        0,
      );
    },
  );

  test(
    'initial fund covers all expenses and leaves reserve with zero saving',
    () {
      expectAmounts(
        calculate(fund: 160, reserve: 60, expenses: [expense(9, 100)]),
        0,
        0,
        0,
      );
    },
  );

  test('fund equal to reserve is insufficient when expenses remain', () {
    expectAmounts(
      calculate(fund: 60, reserve: 60, expenses: [expense(10, 30)]),
      0,
      10,
      10,
    );
  });

  test('zero reserve uses the same monthly calculation', () {
    expectAmounts(calculate(expenses: [expense(11, 90)]), 30, 30, 0);
  });

  test('zero expense is valid alongside paid expenses', () {
    expectAmounts(
      calculate(expenses: [expense(9, 0), expense(11, 90)]),
      30,
      30,
      0,
    );
  });

  test('zero fund and empty expense list still fund the reserve', () {
    expectAmounts(calculate(reserve: 90), 0, 30, 30);
  });

  test('all zero amounts are a successful zero result', () {
    expectAmounts(calculate(expenses: [expense(9, 0)]), 0, 0, 0);
  });

  test('target equals reference: one contribution, expense, and reserve', () {
    expectAmounts(
      calculate(
        fund: 20,
        reserve: 60,
        target: const YearMonth(2026, 9),
        expenses: [expense(9, 100)],
      ),
      80,
      140,
      60,
    );
  });

  test('two months across year boundary both count', () {
    expectAmounts(
      calculateRepairReserve(
        referenceMonth: const YearMonth(2026, 12),
        currentCarFundYen: 0,
        reserveTargetMonth: const YearMonth(2027, 1),
        largeRepairReserveYen: 100,
        plannedExpenses: [],
      ),
      0,
      50,
      50,
    );
  });

  test('fractional requirements round up to one yen', () {
    expectAmounts(
      calculate(reserve: 2, expenses: [expense(11, 100)]),
      34,
      34,
      0,
    );
    expectAmounts(calculate(reserve: 100), 0, 34, 34);
    expectAmounts(calculate(expenses: [expense(10, 101)]), 51, 51, 0);
  });

  test(
    'unsorted mutable and unmodifiable input retain every original item',
    () {
      final input = [expense(11, 30), expense(9, 10), expense(10, 20)];
      final original = List<PlannedExpense>.of(input);
      expectAmounts(calculate(expenses: input), 20, 20, 0);
      expect(input, orderedEquals(original));
      expectAmounts(
        calculate(expenses: List<PlannedExpense>.unmodifiable(input)),
        20,
        20,
        0,
      );
    },
  );

  final invalidCases = <String, RepairReserveCalculationResult Function()>{
    'past target': () => calculate(target: const YearMonth(2026, 8)),
    'negative fund': () => calculate(fund: -1),
    'negative reserve': () => calculate(reserve: -1),
    'negative expense': () => calculate(expenses: [expense(10, -1)]),
    'negative expense before period': () =>
        calculate(expenses: [expense(8, -1)]),
    'negative expense after period': () =>
        calculate(expenses: [expense(12, -1)]),
  };
  for (final entry in invalidCases.entries) {
    test('${entry.key} fails without correcting or discarding input', () {
      final result = entry.value();
      expect(result, isA<RepairReserveFailure>());
      expect(
        (result as RepairReserveFailure).error,
        RepairReserveError.invalidInput,
      );
    });
  }
}
