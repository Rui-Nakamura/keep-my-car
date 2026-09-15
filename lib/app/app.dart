import 'package:flutter/material.dart';

import '../features/home/presentation/home_display_data.dart';
import '../features/home/presentation/home_screen.dart';
import '../sample_data/golden_sample.dart';
import '../sample_data/golden_sample_expected_results.dart';
import 'theme/app_theme.dart';

class KeepMyCarApp extends StatelessWidget {
  const KeepMyCarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keep My Car',
    theme: AppTheme.light,
    themeMode: ThemeMode.light,
    home: HomeScreen(
      car: goldenSample.car,
      owner: goldenSample.owner,
      referenceMonth: goldenSample.referenceMonth,
      goal: goldenSample.goal,
      reserve: goldenSample.reserve,
      plannedExpenses: goldenSample.plannedExpenses,
      displayData: const HomeDisplayData(
        displayRequiredMonthlySavingYen:
            GoldenSampleExpectedResults.displayRequiredMonthlySavingYen,
        displayMonthlyMaintenanceYen:
            GoldenSampleExpectedResults.displayMonthlyMaintenanceYen,
        displayMonthlyCarBudgetYen:
            GoldenSampleExpectedResults.displayMonthlyCarBudgetYen,
        bottleneckMonth: GoldenSampleExpectedResults.bottleneckMonth,
        ownershipEndMonth: GoldenSampleExpectedResults.ownershipEndMonth,
        remainingYears: GoldenSampleExpectedResults.remainingYears,
        remainingMonths: GoldenSampleExpectedResults.remainingMonths,
        approximateCarAgeAtGoalYears:
            GoldenSampleExpectedResults.approximateCarAgeAtGoalYears,
        approximateMileageAtGoalKm:
            GoldenSampleExpectedResults.approximateMileageAtGoalKm,
      ),
    ),
  );
}
