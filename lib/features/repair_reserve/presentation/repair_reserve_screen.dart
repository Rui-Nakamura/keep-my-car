import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/update_feedback.dart';
import '../../../domain/models/major_repair_reserve.dart';
import '../../../domain/models/ownership_goal.dart';
import '../../../domain/repair_reserve_calculator.dart';
import '../../home/presentation/home_format.dart';

class RepairReserveScreen extends StatelessWidget {
  const RepairReserveScreen({
    super.key,
    required this.ownershipGoal,
    required this.reserve,
    required this.result,
    this.updatePending = false,
    this.deltaYen,
    this.onViewed,
  });

  final OwnershipGoal ownershipGoal;
  final MajorRepairReserve reserve;
  final RepairReserveCalculationResult result;
  final bool updatePending;
  final int? deltaYen;
  final VoidCallback? onViewed;

  @override
  Widget build(BuildContext context) => UpdateFeedback(
    pending: updatePending,
    duration: const Duration(milliseconds: 1900),
    onViewed: onViewed,
    builder: (context, emphasis) {
      final text = Theme.of(context).textTheme;
      final result = this.result;
      return Scaffold(
        appBar: AppBar(title: const Text('大型修理への備え')),
        body: SafeArea(
          child: Container(
            key: const ValueKey('reserve-emphasis'),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.5 * emphasis),
                width: 2,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenMargin,
                vertical: AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (updatePending) ...[
                    const Text(
                      '大型修理への備えを更新しました',
                      key: ValueKey('reserve-update-text'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text('保有目標', style: text.bodyLarge),
                  Text('${ownershipGoal.targetAge}歳まで', style: text.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Text('備え目標', style: text.bodyLarge),
                  Text('${reserve.targetAge}歳まで', style: text.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Text('想定大型修理', style: text.bodyLarge),
                  Text(formatYen(reserve.amountYen), style: text.titleLarge),
                  const SizedBox(height: AppSpacing.section),
                  if (result is RepairReserveSuccess) ...[
                    Text('必要な積立額', style: text.titleLarge),
                    const SizedBox(height: AppSpacing.lg),
                    Text('予定費のみ', style: text.bodyLarge),
                    Text(
                      '月 ${formatYen(result.plannedExpensesOnlyMonthlyYen)}',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('大型修理込み', style: text.titleLarge),
                    Text(
                      '月 ${formatYen(result.repairIncludedMonthlyYen)}',
                      style: text.displayMedium!.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (updatePending && deltaYen != null && deltaYen != 0) ...[
                      Text(
                        '前回の試算より ${deltaYen! > 0 ? '＋' : '−'}${formatYen(deltaYen!.abs())} / 月',
                        key: const ValueKey('reserve-delta'),
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Text('大型修理への備え分', style: text.bodyLarge),
                    Text(
                      '＋${formatYen(result.additionalMonthlyYen)}／月',
                      style: text.headlineLarge,
                    ),
                    const SizedBox(height: AppSpacing.section),
                    Text(
                      '登録済みの予定費を支払いながら、${reserve.targetAge}歳時点で大型修理用の資金を確保できるように計算しています。',
                      style: text.bodyLarge,
                    ),
                  ] else ...[
                    Text('計算できません', style: text.titleLarge),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '計画データに確認が必要な項目があります。\n計画設定を見直してください。',
                      style: text.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text('※大型修理の発生時期を予測するものではありません。', style: text.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
