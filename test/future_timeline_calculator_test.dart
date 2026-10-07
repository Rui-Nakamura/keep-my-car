import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/timeline/future_timeline_calculator.dart';

int _nextExpenseId = 1;

PlannedExpense expense(String name, int year, int month, int amount) =>
    PlannedExpense(
      id: _nextExpenseId++,
      name: name,
      plannedMonth: YearMonth(year, month),
      amountYen: amount,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );

void main() {
  for (final scenario in [
    (
      name: 'future target preserves Golden Sample endpoint',
      reference: const YearMonth(2026, 9),
      birth: const YearMonth(1970, 4),
      target: const YearMonth(2040, 4),
      rows: 15,
      expected: (2040, 70, 21, 99333),
    ),
    (
      name: 'same-year future target uses actual target month',
      reference: const YearMonth(2026, 4),
      birth: const YearMonth(1970, 10),
      target: const YearMonth(2026, 10),
      rows: 1,
      expected: (2026, 56, 8, 47000),
    ),
    (
      name: 'same-year past target uses current values',
      reference: const YearMonth(2026, 9),
      birth: const YearMonth(1970, 6),
      target: const YearMonth(2026, 4),
      rows: 1,
      expected: (2026, 56, 8, 45000),
    ),
    (
      name: 'previous-year target keeps one current row',
      reference: const YearMonth(2026, 9),
      birth: const YearMonth(1970, 6),
      target: const YearMonth(2025, 4),
      rows: 1,
      expected: (2026, 56, 8, 45000),
    ),
    (
      name: 'target equal to reference month uses that month',
      reference: const YearMonth(2026, 9),
      birth: const YearMonth(1970, 6),
      target: const YearMonth(2026, 9),
      rows: 1,
      expected: (2026, 56, 8, 45000),
    ),
  ]) {
    test(scenario.name, () {
      final years = calculateFutureTimeline(
        referenceMonth: scenario.reference,
        birthMonth: scenario.birth,
        firstRegistrationMonth: const YearMonth(2018, 8),
        ownershipTargetMonth: scenario.target,
        currentMileageKm: 45000,
        annualMileageKm: 4000,
        plannedExpenses: [],
      );
      expect(years, hasLength(scenario.rows));
      expect(years.first.year, scenario.reference.year);
      expect(years.first.isCurrent, isTrue);
      expect(years.where((year) => year.isCurrent), hasLength(1));
      final last = years.last;
      expect((
        last.year,
        last.ownerAge,
        last.carAge,
        last.mileageKm,
      ), scenario.expected);
    });
  }

  test('exact month boundaries reuse the formal range rule', () {
    final years = calculateFutureTimeline(
      referenceMonth: const YearMonth(2026, 9),
      birthMonth: const YearMonth(1970, 4),
      firstRegistrationMonth: const YearMonth(2018, 8),
      ownershipTargetMonth: const YearMonth(2027, 4),
      currentMileageKm: 45000,
      annualMileageKm: 4000,
      plannedExpenses: [
        expense('before', 2026, 8, 999),
        expense('current', 2026, 9, 10),
        expense('target', 2027, 4, 20),
        expense('after', 2027, 5, 999),
      ],
    );
    expect(years.map((y) => y.totalYen), [10, 20]);
    expect(years.last.ownerAge, 57);
    expect(years.last.carAge, 8);
    expect(years.last.mileageKm, 47333);
  });
  test('target-bounded data preserves boundaries, stable order, totals and original input', () {
    final input = [
      expense('outside after', 2036, 1, 99),
      expense('same first', 2027, 10, 30),
      expense('zero', 2028, 1, 0),
      expense('same second', 2027, 10, 20),
      expense('earlier', 2027, 4, 100),
      expense('outside before', 2025, 12, 99),
      expense('January', 2026, 1, 10),
      expense('December', 2035, 12, 20),
    ];
    final original = List.of(input);
    final years = calculateFutureTimeline(
      referenceMonth: const YearMonth(2026, 1),
      birthMonth: const YearMonth(1970, 1),
      firstRegistrationMonth: const YearMonth(2018, 1),
      ownershipTargetMonth: const YearMonth(2035, 12),
      currentMileageKm: 45000,
      annualMileageKm: 4000,
      plannedExpenses: input,
    );
    expect(years.length, 10);
    expect(years.first.expenses.single.name, 'January');
    expect(years.last.expenses.single.name, 'December');
    expect(years[1].expenses.map((e) => e.name), [
      'earlier',
      'same first',
      'same second',
    ]);
    expect(years[1].totalYen, 150);
    expect(years[2].expenses.length, 1);
    expect(years[2].totalYen, 0);
    expect(years[3].expenses, isEmpty);
    expect(years[3].totalYen, 0);
    expect(
      (
        years.last.year,
        years.last.ownerAge,
        years.last.carAge,
        years.last.mileageKm,
      ),
      (2035, 65, 17, 84666),
    );
    expect(years.where((year) => year.isCurrent).length, 1);
    expect(input, orderedEquals(original));
    expect(() => years.clear(), throwsUnsupportedError);
    expect(() => years[1].expenses.clear(), throwsUnsupportedError);
  });
  test('zero annual mileage and different reference year have no monthly adjustment', () {
    final years = calculateFutureTimeline(
      referenceMonth: const YearMonth(2040, 1),
      birthMonth: const YearMonth(1980, 1),
      firstRegistrationMonth: const YearMonth(2030, 1),
      ownershipTargetMonth: const YearMonth(2049, 1),
      currentMileageKm: 12345,
      annualMileageKm: 0,
      plannedExpenses: [],
    );
    expect(years.first.year, 2040);
    expect(years.last.year, 2049);
    expect(years.every((year) => year.mileageKm == 12345), isTrue);
  });
}
