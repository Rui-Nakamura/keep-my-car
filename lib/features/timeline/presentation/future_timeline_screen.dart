import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';
import '../../home/presentation/home_format.dart';

class FutureTimelineScreen extends StatelessWidget {
  const FutureTimelineScreen({
    super.key,
    required this.currentYear,
    required this.currentOwnerAge,
    required this.currentCarAge,
    required this.currentMileageKm,
    required this.annualMileageKm,
    required this.plannedExpenses,
  });

  final int currentYear;
  final int currentOwnerAge;
  final int currentCarAge;
  final int currentMileageKm;
  final int annualMileageKm;
  final List<PlannedExpense> plannedExpenses;

  @override
  Widget build(BuildContext context) {
    // Sort a copy, with original positions preserving same-month input order.
    final sorted =
        plannedExpenses.indexed.where((entry) {
          final year = entry.$2.plannedMonth.year;
          return year >= currentYear && year < currentYear + 10;
        }).toList()..sort((a, b) {
          final order = a.$2.plannedMonth.compareTo(b.$2.plannedMonth);
          return order != 0 ? order : a.$1.compareTo(b.$1);
        });
    final expensesByYear = <int, List<PlannedExpense>>{};
    for (final entry in sorted) {
      (expensesByYear[entry.$2.plannedMonth.year] ??= []).add(entry.$2);
    }
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('未来タイムライン')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('これから10年間の計画', style: text.headlineLarge),
              const SizedBox(height: AppSpacing.xxl),
              for (var offset = 0; offset < 10; offset++)
                _TimelineYear(
                  year: currentYear + offset,
                  ownerAge: currentOwnerAge + offset,
                  carAge: currentCarAge + offset,
                  mileageKm: currentMileageKm + annualMileageKm * offset,
                  isCurrent: offset == 0,
                  expenses: expensesByYear[currentYear + offset] ?? const [],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineYear extends StatelessWidget {
  const _TimelineYear({
    required this.year,
    required this.ownerAge,
    required this.carAge,
    required this.mileageKm,
    required this.isCurrent,
    required this.expenses,
  });

  final int year;
  final int ownerAge;
  final int carAge;
  final int mileageKm;
  final bool isCurrent;
  final List<PlannedExpense> expenses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final milestone = const {60, 65, 70, 75}.contains(ownerAge);
    return Container(
      key: ValueKey('timeline-year-$year'),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        bottom: AppSpacing.section,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Wrap(
              spacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$year年', style: text.titleLarge),
                if (isCurrent) Text('現在', style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                '$ownerAge歳',
                style: milestone ? text.titleMedium : text.bodyLarge,
              ),
              Text('車齢$carAge年', style: text.bodyLarge),
              Text('約${formatKm(mileageKm)}', style: text.bodyLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (expenses.isEmpty)
            Text('予定費なし', style: text.bodyMedium)
          else ...[
            for (final expense in expenses)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(expense.name, style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
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
            Text(
              '年間予定費 ${formatYen(expenses.fold<int>(0, (sum, expense) => sum + expense.amountYen))}',
              style: text.titleMedium,
            ),
          ],
        ],
      ),
    );
  }
}
