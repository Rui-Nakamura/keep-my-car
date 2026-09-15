import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';
import '../../home/presentation/home_format.dart';

class PlannedExpensesScreen extends StatelessWidget {
  const PlannedExpensesScreen({super.key, required this.plannedExpenses});

  final List<PlannedExpense> plannedExpenses;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Original positions make same-month order explicit without mutating input.
    final sorted = plannedExpenses.indexed.toList()
      ..sort((a, b) {
        final monthOrder = a.$2.plannedMonth.compareTo(b.$2.plannedMonth);
        return monthOrder != 0 ? monthOrder : a.$1.compareTo(b.$1);
      });
    final years = <int, List<PlannedExpense>>{};
    for (final entry in sorted) {
      (years[entry.$2.plannedMonth.year] ??= []).add(entry.$2);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('愛車予定費')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${plannedExpenses.length}件の予定', style: text.bodyMedium),
              if (plannedExpenses.isEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text('予定はありません', style: text.bodyLarge),
              ],
              for (final year in years.entries)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.section),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Wrap(
                          spacing: AppSpacing.lg,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('${year.key}年', style: text.titleLarge),
                            Text(
                              '合計 ${formatYen(year.value.fold<int>(0, (sum, expense) => sum + expense.amountYen))}',
                              style: text.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      for (final expense in year.value)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(expense.name, style: text.titleMedium),
                              const SizedBox(height: AppSpacing.xs),
                              Wrap(
                                spacing: AppSpacing.lg,
                                runSpacing: AppSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    formatMonth(expense.plannedMonth),
                                    style: text.bodyMedium,
                                  ),
                                  Text(
                                    formatYen(expense.amountYen),
                                    style: text.titleMedium,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
