import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';

import '../plan_test_support.dart';

PlannedExpense expense(int id, int year, int month, int yen) => PlannedExpense(
  id: id,
  name: 'expense $id',
  plannedMonth: YearMonth(year, month),
  amountYen: yen,
  basis: ExpenseBasis.placeholder,
  status: PlannedExpenseStatus.planned,
  memo: null,
);

void main() {
  test('ownership boundary getters use signed month difference without recalculation', () {
    final calls = CalculationCalls();
    for (final entry in [
      (const YearMonth(2026, 9), 163, false),
      (const YearMonth(2039, 9), 7, false),
      (const YearMonth(2030, 4), 120, false),
      (const YearMonth(2040, 4), 0, false),
      (const YearMonth(2040, 5), -1, true),
    ]) {
      final plan = session(
        reference: entry.$1,
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      calls.reset();
      expect(plan.monthsUntilOwnershipTarget, entry.$2);
      expect(plan.ownershipTargetReached, entry.$3);
      expect((calls.timeline, calls.reserve), (0, 0));
    }
    final plan = session();
    plan.apply(conditions(ownership: 80));
    expect(plan.monthsUntilOwnershipTarget, 283);
    expect(plan.ownershipTargetReached, isFalse);
  });

  test('empty summaries are normal and have no next month', () {
    final plan = session(expenses: []);
    expect(plan.ownershipTargetExpensesTotalYen, 0);
    expect(plan.nextExpenseMonth, isNull);
    expect(plan.expensesInNextMonth, isEmpty);
    expect(plan.nextMonthTotalYen, 0);
    expect(plan.nextYearExpensesTotalYen, 0);
    expect(plan.fiveYearExpensesTotalYen, 0);
  });

  test('single zero-cost expense exists independently of its amount', () {
    final item = expense(1, 2027, 1, 0);
    final plan = session(expenses: [item]);
    expect(plan.nextExpenseMonth, const YearMonth(2027, 1));
    expect(plan.expensesInNextMonth, [item]);
    expect(plan.ownershipTargetExpensesTotalYen, 0);
    expect(plan.nextMonthTotalYen, 0);
  });

  test('one paid expense totals correctly with empty next year', () {
    final item = expense(1, 2028, 2, 12345);
    final plan = session(expenses: [item]);
    expect(plan.ownershipTargetExpensesTotalYen, 12345);
    expect(plan.nextExpenseMonth, const YearMonth(2028, 2));
    expect(plan.nextMonthTotalYen, 12345);
    expect(plan.nextYearExpensesTotalYen, 0);
    expect(plan.fiveYearExpensesTotalYen, 12345);
  });

  test(
    'nearest month includes all ties in original order and excludes past',
    () {
      final input = [
        expense(1, 2028, 1, 900),
        expense(2, 2026, 9, 10),
        expense(3, 2026, 8, 800),
        expense(4, 2026, 9, 20),
        expense(5, 2040, 5, 700),
        expense(6, 2040, 4, 40),
      ];
      final plan = session(expenses: input);
      expect(plan.ownershipTargetExpensesTotalYen, 970);
      expect(plan.nextExpenseMonth, const YearMonth(2026, 9));
      expect(plan.expensesInNextMonth, [input[1], input[3]]);
      expect(plan.nextMonthTotalYen, 30);
      expect(() => plan.expensesInNextMonth.clear(), throwsUnsupportedError);
      expect(plan.plannedExpenses, input);
      plan.deleteExpense(2);
      plan.deleteExpense(4);
      expect(plan.nextExpenseMonth, const YearMonth(2028, 1));
      expect(plan.nextMonthTotalYen, 900);
    },
  );

  test('next calendar year and five calendar years match timeline totals', () {
    final plan = session(
      expenses: [
        expense(1, 2026, 8, 999),
        expense(2, 2026, 9, 1),
        expense(3, 2027, 1, 2),
        expense(4, 2027, 12, 3),
        expense(5, 2028, 1, 4),
        expense(6, 2030, 12, 5),
        expense(7, 2031, 1, 6),
      ],
    );
    expect(plan.nextYearExpensesTotalYen, 5);
    expect(plan.nextYearExpensesTotalYen, plan.timeline[1].totalYen);
    expect(plan.fiveYearExpensesTotalYen, 15);
  });

  test('short target truncates aggregates at the exact month', () {
    final plan = session(
      initial: conditions(ownership: 57, age: 57),
      expenses: [
        expense(1, 2026, 9, 1),
        expense(2, 2027, 1, 2),
        expense(3, 2027, 4, 3),
        expense(4, 2027, 5, 99),
        expense(5, 2028, 1, 99),
      ],
    );
    expect(plan.ownershipTargetExpensesTotalYen, 6);
    expect(plan.nextYearExpensesTotalYen, 5);
    expect(plan.fiveYearExpensesTotalYen, 6);
    expect(plan.nextYearExpensesTotalYen, plan.timeline.last.totalYen);
    plan.adoptValidatedConditions(conditions(ownership: 56, age: 56));
    expect(plan.ownershipTargetExpensesTotalYen, 0);
    expect(plan.nextExpenseMonth, isNull);
    expect(plan.nextYearExpensesTotalYen, 0);
    expect(plan.fiveYearExpensesTotalYen, 0);
    expect(plan.plannedExpenses, hasLength(5));
  });

  test('Golden Sample aggregate includes all six expenses through target', () {
    final plan = session();
    expect(plan.ownershipTargetExpensesTotalYen, 2550000);
    expect(plan.nextExpenseMonth, const YearMonth(2027, 4));
    expect(plan.nextMonthTotalYen, 80000);
    expect(plan.nextYearExpensesTotalYen, 80000);
    expect(plan.fiveYearExpensesTotalYen, 300000);
    expect(plan.ownershipTargetOwnerAge, 70);
    expect(plan.ownershipTargetCarAge, 21);
    expect(plan.ownershipTargetMileageKm, 99333);
    expect(plan.timeline, hasLength(15));
    expect(plan.timeline.expand((y) => y.expenses), plan.includedExpenses);
    expect(plan.timeline.fold<int>(0, (sum, y) => sum + y.totalYen), 2550000);
    expect(plan.timeline.singleWhere((y) => y.year == 2037).totalYen, 700000);
    expect(plan.timeline.singleWhere((y) => y.year == 2039).totalYen, 250000);
  });

  for (final targetAge in [55, 56, 57, 65, 70, 80]) {
    test('target age $targetAge determines endpoint with at least one row', () {
      final plan = session(
        initial: conditions(ownership: targetAge, age: targetAge),
        expenses: [],
      );
      final expectedLast = targetAge < 56 ? 2026 : 1970 + targetAge;
      expect(plan.timeline.first.year, 2026);
      expect(plan.timeline.last.year, expectedLast);
      expect(plan.timeline.length, expectedLast - 2026 + 1);
      expect(plan.timeline.where((y) => y.isCurrent), hasLength(1));
      expect(
        plan.timeline.every((y) => y.totalYen == 0 && y.expenses.isEmpty),
        isTrue,
      );
      if (plan.ownershipTargetMonth.compareTo(plan.referenceMonth) >= 0) {
        final last = plan.timeline.last;
        expect(last.ownerAge, plan.ownershipTargetOwnerAge);
        expect(last.carAge, plan.ownershipTargetCarAge);
        expect(last.mileageKm, plan.ownershipTargetMileageKm);
      } else {
        expect(plan.timeline.single.ownerAge, 56);
        expect(plan.timeline.single.carAge, 8);
        expect(plan.timeline.single.mileageKm, 45000);
      }
    });
  }

  for (final month in [3, 4, 5]) {
    test(
      'same-year endpoint uses target or current month across birthday boundaries $month',
      () {
        final plan = session(
          initial: conditions(
            ownership: 60,
            age: 60,
            annual: 2000,
            mileage: 12345,
          ),
          reference: YearMonth(2030, month),
          registration: const YearMonth(2020, 4),
          expenses: [],
        );
        expect(plan.ownershipTargetOwnerAge, 60);
        expect(plan.ownershipTargetCarAge, 10);
        expect(plan.ownershipTargetMileageKm, month == 3 ? 12511 : 12345);
        expect(plan.timeline.single.ownerAge, plan.ownershipTargetOwnerAge);
        expect(plan.timeline.single.carAge, plan.ownershipTargetCarAge);
        expect(plan.timeline.single.mileageKm, plan.ownershipTargetMileageKm);
      },
    );
  }

  test('ownership-only adoption recalculates once; reads and no-op do not recalculate', () {
    final calls = CalculationCalls();
    final plan = session(
      expenses: [],
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    calls.reset();
    plan.adoptValidatedConditions(conditions(ownership: 65));
    expect((calls.timeline, calls.reserve), (1, 0));
    expect(plan.timeline.last.year, 2035);
    expect(plan.timelinePending, isTrue);
    plan.acknowledgeTimeline();
    calls.reset();
    plan.apply(conditions(ownership: 65));
    plan.ownershipTargetExpensesTotalYen;
    plan.nextExpenseMonth;
    plan.expensesInNextMonth;
    plan.ownershipTargetMileageKm;
    plan.timeline;
    expect((calls.timeline, calls.reserve), (0, 0));
    expect(plan.timelinePending, isFalse);
    plan.apply(conditions(ownership: 80));
    expect((calls.timeline, calls.reserve), (1, 0));
    expect(plan.timeline.last.year, 2050);
  });
}
