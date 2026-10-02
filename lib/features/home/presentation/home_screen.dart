import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/save_request.dart';

import '../../../domain/models/car.dart';
import '../../../domain/car_validation.dart';
import '../../car/presentation/car_name_screen.dart';

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
import '../../../app/display_format.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.car,
    required this.onSaveCarName,
    required this.session,
    required this.onApply,
    required this.onNavigate,
    required this.onTimelineViewed,
    required this.onReserveViewed,
    required this.onExpensesChanged,
    required this.onSaveExpense,
    required this.onDeleteExpense,
    this.onDataManagement,
  });
  final PlanSession session;
  final VoidCallback? onDataManagement;
  final Car car;
  final FutureOr<CarNameError?> Function(String) onSaveCarName;
  final FutureOr<Map<PlanField, PlanInputError>> Function(PlanConditions)
  onApply;
  final SaveExpenseRequest onSaveExpense;
  final DeleteExpenseRequest onDeleteExpense;
  final VoidCallback onNavigate;
  final VoidCallback onTimelineViewed;
  final VoidCallback onReserveViewed;
  final VoidCallback onExpensesChanged;

  Future<void> _editCarName(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CarNameScreen(name: car.name, onSave: onSaveCarName),
      ),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('愛車名を更新しました')));
    }
  }

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
              const SizedBox(height: AppSpacing.lg),
              Text(car.name, style: text.titleLarge),
              TextButton(
                onPressed: () => _editCarName(context),
                child: const Text('愛車名を編集'),
              ),
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
                    onSaveExpense: onSaveExpense,
                    onDeleteExpense: onDeleteExpense,
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
                    onDataManagement: onDataManagement,
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
