import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/update_feedback.dart';
import '../future_timeline_calculator.dart';
import '../../../domain/models/planned_expense.dart';
import '../../../app/display_format.dart';

class FutureTimelineScreen extends StatelessWidget {
  const FutureTimelineScreen({
    super.key,
    required this.years,
    this.updatePending = false,
    this.onViewed,
  });

  final List<TimelineYearData> years;
  final bool updatePending;
  final VoidCallback? onViewed;

  @override
  Widget build(BuildContext context) => UpdateFeedback(
    pending: updatePending,
    duration: const Duration(milliseconds: 1600),
    onViewed: onViewed,
    builder: (context, emphasis) {
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
                if (updatePending) ...[
                  const Text(
                    '未来タイムラインを更新しました',
                    key: ValueKey('timeline-update-text'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                for (final year in years)
                  _TimelineYear(
                    year: year.year,
                    ownerAge: year.ownerAge,
                    carAge: year.carAge,
                    mileageKm: year.mileageKm,
                    isCurrent: year.isCurrent,
                    expenses: year.expenses,
                    totalYen: year.totalYen,
                    emphasis: emphasis,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TimelineYear extends StatelessWidget {
  const _TimelineYear({
    required this.year,
    required this.ownerAge,
    required this.carAge,
    required this.mileageKm,
    required this.isCurrent,
    required this.expenses,
    required this.totalYen,
    required this.emphasis,
  });

  final int year;
  final int ownerAge;
  final int carAge;
  final int mileageKm;
  final bool isCurrent;
  final List<PlannedExpense> expenses;
  final int totalYen;
  final double emphasis;

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
          Container(
            key: ValueKey('timeline-emphasis-$year'),
            color: theme.colorScheme.primary.withValues(alpha: 0.10 * emphasis),
            child: Wrap(
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
            Text('年間予定費 ${formatYen(totalYen)}', style: text.titleMedium),
          ],
        ],
      ),
    );
  }
}
