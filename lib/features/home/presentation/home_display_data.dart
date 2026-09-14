import '../../../domain/models/year_month.dart';

/// Immutable display values supplied by the application.
class HomeDisplayData {
  const HomeDisplayData({
    required this.displayRequiredMonthlySavingYen,
    required this.displayMonthlyMaintenanceYen,
    required this.displayMonthlyCarBudgetYen,
    required this.bottleneckMonth,
    required this.ownershipEndMonth,
    required this.remainingYears,
    required this.remainingMonths,
    required this.approximateCarAgeAtGoalYears,
    required this.approximateMileageAtGoalKm,
  });

  final int displayRequiredMonthlySavingYen;
  final int displayMonthlyMaintenanceYen;
  final int displayMonthlyCarBudgetYen;
  final YearMonth bottleneckMonth;
  final YearMonth ownershipEndMonth;
  final int remainingYears;
  final int remainingMonths;
  final int approximateCarAgeAtGoalYears;
  final int approximateMileageAtGoalKm;
}
