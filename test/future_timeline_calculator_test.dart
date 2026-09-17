import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/timeline/future_timeline_calculator.dart';

PlannedExpense expense(String name, int year, int month, int amount) =>
    PlannedExpense(
      name: name,
      plannedMonth: YearMonth(year, month),
      amountYen: amount,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );

void main() {
  test('ten-year data preserves boundaries, stable order, totals and original input', () {
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
      currentYear: 2026,
      currentOwnerAge: 56,
      currentCarAge: 8,
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
      (2035, 65, 17, 81000),
    );
    expect(years.where((year) => year.isCurrent).length, 1);
    expect(input, orderedEquals(original));
    expect(() => years.clear(), throwsUnsupportedError);
    expect(() => years[1].expenses.clear(), throwsUnsupportedError);
  });
  test('zero annual mileage and different reference year have no monthly adjustment', () {
    final years = calculateFutureTimeline(
      currentYear: 2040,
      currentOwnerAge: 60,
      currentCarAge: 10,
      currentMileageKm: 12345,
      annualMileageKm: 0,
      plannedExpenses: [],
    );
    expect(years.first.year, 2040);
    expect(years.last.year, 2049);
    expect(years.every((year) => year.mileageKm == 12345), isTrue);
  });
}
