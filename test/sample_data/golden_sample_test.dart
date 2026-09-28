import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/maintenance_cost.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';
import 'package:keep_my_car/sample_data/golden_sample_expected_results.dart';

void main() {
  test('Approved car, owner, goal and funding inputs are preserved', () {
    expect(goldenSample.referenceMonth, const YearMonth(2026, 9));
    expect(goldenSample.car.name, 'メルセデスAMG E53');
    expect(goldenSample.car.firstRegistrationMonth, const YearMonth(2018, 8));
    expect(goldenSample.car.currentMileageKm, 45000);
    expect(goldenSample.car.mileageCheckedMonth, const YearMonth(2026, 9));
    expect(goldenSample.car.annualMileageKm, 4000);
    expect(goldenSample.owner.birthMonth, const YearMonth(1970, 4));
    expect(goldenSample.goal.targetAge, 70);
    expect(goldenSample.currentCarFundYen, 500000);
    expect(goldenSample.reserve.amountYen, 2000000);
    expect(goldenSample.reserve.targetAge, 65);
  });

  test('All six approved planned expenses and their total are preserved', () {
    expect(goldenSample.plannedExpenses, hasLength(6));
    expect(
      goldenSample.plannedExpenses
          .map((e) => (e.plannedMonth, e.name, e.amountYen))
          .toList(),
      const [
        (YearMonth(2027, 4), '12Vバッテリー', 80000),
        (YearMonth(2028, 8), 'タイヤ', 220000),
        (YearMonth(2031, 6), 'ブレーキ一式', 800000),
        (YearMonth(2034, 9), '48Vバッテリー', 500000),
        (YearMonth(2037, 8), '足回り', 700000),
        (YearMonth(2039, 4), 'タイヤ', 250000),
      ],
    );
    for (final expense in goldenSample.plannedExpenses) {
      expect(expense.status, PlannedExpenseStatus.planned);
      expect(expense.basis, ExpenseBasis.placeholder);
      expect(expense.memo, isNull);
    }
    // Fixture integrity check only; not a planning calculation.
    expect(
      goldenSample.plannedExpenses.fold<int>(0, (sum, e) => sum + e.amountYen),
      2550000,
    );
  });

  test('All nine maintenance inputs retain amounts and frequencies', () {
    expect(goldenSample.maintenanceCosts, hasLength(9));
    expect(
      goldenSample.maintenanceCosts
          .map((c) => (c.name, c.amountYen, c.frequency))
          .toList(),
      const [
        ('自動車税等', 51000, MaintenanceFrequency.yearly),
        ('任意保険', 120000, MaintenanceFrequency.yearly),
        ('駐車場', 18000, MaintenanceFrequency.monthly),
        ('燃料', 12000, MaintenanceFrequency.monthly),
        ('高速道路', 5000, MaintenanceFrequency.monthly),
        ('洗車', 4000, MaintenanceFrequency.monthly),
        ('車検法定費用', 70000, MaintenanceFrequency.everyTwoYears),
        ('車検点検・整備基本費用', 100000, MaintenanceFrequency.everyTwoYears),
        ('法定12ヶ月点検', 40000, MaintenanceFrequency.yearly),
      ],
    );
  });

  test('Fixture lists cannot be mutated', () {
    expect(() => goldenSample.plannedExpenses.clear(), throwsUnsupportedError);
    expect(() => goldenSample.maintenanceCosts.clear(), throwsUnsupportedError);
  });

  test('Approved display expectations remain independent fixed values', () {
    expect(GoldenSampleExpectedResults.displayRequiredMonthlySavingYen, 30000);
    expect(
      GoldenSampleExpectedResults
          .displayRequiredMonthlySavingWithoutExpensesYen,
      15000,
    );
    expect(
      GoldenSampleExpectedResults.bottleneckMonth,
      const YearMonth(2035, 4),
    );
    expect(
      GoldenSampleExpectedResults.ownershipEndMonth,
      const YearMonth(2040, 4),
    );
    expect(
      (
        GoldenSampleExpectedResults.remainingYears,
        GoldenSampleExpectedResults.remainingMonths,
      ),
      (13, 7),
    );
    expect(GoldenSampleExpectedResults.approximateCarAgeAtGoalYears, 22);
    expect(GoldenSampleExpectedResults.approximateMileageAtGoalKm, 99000);
    expect(GoldenSampleExpectedResults.displayMonthlyMaintenanceYen, 64000);
    expect(GoldenSampleExpectedResults.displayMonthlyCarBudgetYen, 94000);
  });
}
