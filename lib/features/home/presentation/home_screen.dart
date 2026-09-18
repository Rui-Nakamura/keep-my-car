import 'package:flutter/material.dart';

import '../../../app/plan_session.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/models/ownership_goal.dart';
import '../../../domain/models/major_repair_reserve.dart';
import '../../../domain/plan_conditions_validation.dart';
import '../../timeline/presentation/future_timeline_screen.dart';
import '../../planned_expenses/presentation/planned_expenses_screen.dart';
import '../../repair_reserve/presentation/repair_reserve_screen.dart';
import '../../settings/presentation/plan_settings_screen.dart';
import 'home_format.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onApply,
    required this.onNavigate,
    required this.onTimelineViewed,
    required this.onReserveViewed,
    required this.onExpensesChanged,
  });
  final PlanSession session;
  final Map<PlanField, PlanInputError> Function(PlanConditions) onApply;
  final VoidCallback onNavigate;
  final VoidCallback onTimelineViewed;
  final VoidCallback onReserveViewed;
  final VoidCallback onExpensesChanged;

  void _open(BuildContext context, Widget screen) {
    // The screen is constructed before the builder, fixing this visit's snapshot.
    onNavigate();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final conditions = session.conditions;
    final notice = switch (session.homeUpdate) {
      HomeUpdate.timeline => '未来タイムラインを更新しました',
      HomeUpdate.reserve => '大型修理への備えを更新しました',
      HomeUpdate.both => '未来タイムラインと大型修理への備えを更新しました',
      null => null,
    };
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
              Text(
                '${conditions.ownershipTargetAge}歳まで保有',
                style: text.displayMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '${conditions.reserveTargetAge}歳までに大型修理用として${formatYen(conditions.largeRepairReserveYen)}を備える',
                style: text.titleLarge,
              ),
              if (notice != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    notice,
                    key: const ValueKey('home-update'),
                    style: text.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.section),
              TextButton(
                onPressed: () => _open(
                  context,
                  FutureTimelineScreen(
                    years: session.timeline,
                    updatePending: session.timelinePending,
                    onViewed: onTimelineViewed,
                  ),
                ),
                child: const Text('未来タイムラインを見る'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('大型修理への備え', style: text.titleLarge),
              TextButton(
                onPressed: () => _open(
                  context,
                  RepairReserveScreen(
                    ownershipGoal: OwnershipGoal(
                      targetAge: session.conditions.ownershipTargetAge,
                    ),
                    reserve: MajorRepairReserve(
                      amountYen: session.conditions.largeRepairReserveYen,
                      targetAge: session.conditions.reserveTargetAge,
                    ),
                    result: session.reserveResult,
                    updatePending: session.reservePending,
                    deltaYen: session.reserveDeltaYen,
                    onViewed: onReserveViewed,
                  ),
                ),
                child: const Text('詳しく見る'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => _open(
                  context,
                  PlannedExpensesScreen(
                    session: session,
                    onChanged: onExpensesChanged,
                  ),
                ),
                child: const Text('予定費を見る・追加する'),
              ),
              const SizedBox(height: AppSpacing.section),
              OutlinedButton(
                onPressed: () => _open(
                  context,
                  PlanSettingsScreen(
                    conditions: session.conditions,
                    birthMonth: session.birthMonth,
                    referenceMonth: session.referenceMonth,
                    onApply: onApply,
                  ),
                ),
                child: const Text('設定'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
