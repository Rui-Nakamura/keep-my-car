import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/car.dart';
import '../../../domain/models/major_repair_reserve.dart';
import '../../../domain/models/ownership_goal.dart';
import '../../../domain/models/planned_expense.dart';
import 'home_display_data.dart';
import 'home_format.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.car,
    required this.goal,
    required this.reserve,
    required this.plannedExpenses,
    required this.displayData,
  });

  final Car car;
  final OwnershipGoal goal;
  final MajorRepairReserve reserve;
  final List<PlannedExpense> plannedExpenses;
  final HomeDisplayData displayData;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final nextExpense = plannedExpenses.first;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Keep My Car', style: text.headlineLarge),
              const SizedBox(height: AppSpacing.xxl),
              Text('${goal.targetAge}歳まで', style: text.displayLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'あと${displayData.remainingYears}年${displayData.remainingMonths}か月',
                style: text.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(car.name, style: text.bodyLarge),
              const SizedBox(height: AppSpacing.xxl),
              _SavingTargetCard(
                amountYen: displayData.displayRequiredMonthlySavingYen,
              ),
              const SizedBox(height: AppSpacing.section),
              _HomeSection(
                title: '愛車のために見ておきたい月額',
                children: [
                  Text(
                    '約${formatYen(displayData.displayMonthlyCarBudgetYen)} / 月',
                    style: text.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('普段の維持費', style: text.bodyLarge),
                  Text(
                    '約${formatYen(displayData.displayMonthlyMaintenanceYen)}',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('将来への積立', style: text.bodyLarge),
                  Text(
                    formatYen(displayData.displayRequiredMonthlySavingYen),
                    style: text.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _HomeSection(
                title: '積立額の決め手',
                children: [
                  Text(
                    formatMonth(displayData.bottleneckMonth),
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('この時点までに必要な資金が、現在の積立目安を決めています。', style: text.bodyLarge),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _HomeSection(
                title: '未来の自分と愛車',
                children: [
                  Text('${goal.targetAge}歳のあなた', style: text.headlineLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Text('愛車', style: text.bodyLarge),
                  Text(
                    '約${displayData.approximateCarAgeAtGoalYears}年目',
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('走行距離', style: text.bodyLarge),
                  Text(
                    '約${formatKm(displayData.approximateMileageAtGoalKm)}',
                    style: text.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _HomeSection(
                title: '大型修理への備え',
                children: [
                  Text(
                    formatReserveYen(reserve.amountYen),
                    style: text.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('${reserve.targetAge}歳までに', style: text.bodyLarge),
                ],
              ),
              const SizedBox(height: AppSpacing.section),
              _HomeSection(
                title: '予定費',
                children: [
                  Text('次回', style: text.bodyMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatMonth(nextExpense.plannedMonth),
                    style: text.bodyLarge,
                  ),
                  Text(nextExpense.name, style: text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatYen(nextExpense.amountYen),
                    style: text.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('${plannedExpenses.length}件の予定', style: text.bodyMedium),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(onPressed: () {}, child: const Text('予定費を追加')),
                ],
              ),
              const SizedBox(height: AppSpacing.xxxl),
              const Divider(),
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSizes.buttonMinHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text('設定', style: text.titleMedium)),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingTargetCard extends StatelessWidget {
  const _SavingTargetCard({required this.amountYen});

  final int amountYen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.importantCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('今からの積立目安', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Text(
              '月${formatYen(amountYen)}',
              style: theme.textTheme.displayMedium!.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Common spacing for the secondary, card-free sections.
class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(height: AppSpacing.lg),
      ...children,
    ],
  );
}
