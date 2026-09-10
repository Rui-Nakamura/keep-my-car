import '../domain/models/year_month.dart';

/// Approved display expectations, separate from inputs.
/// These are fixed reference values, not outputs from an implemented engine.
abstract final class GoldenSampleExpectedResults {
  static const int displayRequiredMonthlySavingYen = 30000;
  static const bottleneckMonth = YearMonth(2035, 4);
  static const ownershipEndMonth = YearMonth(2040, 4);
  static const int remainingYears = 13;
  static const int remainingMonths = 7;
  static const int approximateCarAgeAtGoalYears = 22;
  static const int approximateMileageAtGoalKm = 99000;
  static const int displayMonthlyMaintenanceYen = 64000;
  static const int displayMonthlyCarBudgetYen = 94000;
  static const int displayRequiredMonthlySavingWithoutExpensesYen = 15000;
}
