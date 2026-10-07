import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/display_format.dart';
import '../../../app/plan_session.dart';
import '../../../app/save_request.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/car_validation.dart';
import '../../../domain/models/car.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/plan_conditions_validation.dart';
import '../../car/presentation/car_name_screen.dart';
import '../../planned_expenses/presentation/planned_expense_editor.dart';
import '../../planned_expenses/presentation/planned_expenses_screen.dart';
import '../../settings/presentation/plan_settings_screen.dart';
import '../../timeline/presentation/future_timeline_screen.dart';

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
    // Construct before the builder to fix this visit's feedback snapshot.
    onNavigate();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _settings(BuildContext context) => _open(
    context,
    PlanSettingsScreen(
      conditions: session.conditions,
      birthMonth: session.birthMonth,
      referenceMonth: session.referenceMonth,
      onApply: onApply,
      onDataManagement: onDataManagement,
    ),
  );

  void _expenses(BuildContext context) => _open(
    context,
    PlannedExpensesScreen(
      session: session,
      onChanged: onExpensesChanged,
      onSaveExpense: onSaveExpense,
      onDeleteExpense: onDeleteExpense,
    ),
  );

  Future<void> _addExpense(BuildContext context) async {
    onNavigate();
    final change = await Navigator.of(context).push<ExpenseChange>(
      MaterialPageRoute<ExpenseChange>(
        builder: (_) => PlannedExpenseEditor(
          session: session,
          onSave: onSaveExpense,
          onDelete: onDeleteExpense,
        ),
      ),
    );
    if (!context.mounted || change != ExpenseChange.added) return;
    // Suppress this operation's Home text only; preserve screen pending flags.
    session.consumeHomeUpdate();
    onExpensesChanged();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('予定費を追加しました')));
  }

  String _remainingPeriod() {
    final months = session.monthsUntilOwnershipTarget;
    if (months == 0) return '今月が保有目標です';
    final years = months ~/ 12;
    final remainder = months % 12;
    return 'あと${years > 0 ? '$years年' : ''}${remainder > 0 ? '$remainderか月' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Branch before reading normal target summaries: past targets use no mixed
    // reference/target-time ages, distances or expense aggregates.
    final reached = session.ownershipTargetReached;
    final notice = switch (session.homeUpdate) {
      HomeUpdate.timeline || HomeUpdate.both => '未来タイムラインを更新しました',
      HomeUpdate.reserve || null => null,
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
              OutlinedButton(
                onPressed: () => _settings(context),
                child: const Text('設定'),
              ),
              const SizedBox(height: AppSpacing.section),
              if (reached) ...[
                Text('保有目標に到達しています', style: text.displayMedium),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '設定していた保有目標は ${formatMonth(session.ownershipTargetMonth)}でした',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('これからも乗り続ける場合は、新しい保有目標を設定してください。', style: text.bodyLarge),
                OutlinedButton(
                  onPressed: () => _settings(context),
                  child: const Text('保有目標を見直す'),
                ),
                if (session.plannedExpenses.isNotEmpty)
                  TextButton(
                    onPressed: () => _expenses(context),
                    child: const Text('予定費を確認する'),
                  ),
              ] else ...[
                Text(
                  '${session.ownershipTargetOwnerAge}歳まで乗る計画',
                  style: text.displayMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(_remainingPeriod(), style: text.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '保有目標時の車齢${session.ownershipTargetCarAge}年',
                  style: text.bodyLarge,
                ),
                Text('保有目標時の想定走行距離', style: text.bodyLarge),
                Text(
                  formatHomeMileageKm(session.ownershipTargetMileageKm),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.section),
                if (session.includedExpenses.isNotEmpty) ...[
                  Text(
                    '${session.ownershipTargetOwnerAge}歳までの予定費',
                    style: text.titleLarge,
                  ),
                  Text(
                    formatYen(session.ownershipTargetExpensesTotalYen),
                    style: text.headlineSmall,
                  ),
                  Text('登録している予定費の合計です', style: text.bodyMedium),
                  const SizedBox(height: AppSpacing.section),
                  Text('次の予定費', style: text.titleLarge),
                  Text(
                    formatMonth(session.nextExpenseMonth!),
                    style: text.bodyLarge,
                  ),
                  Text(
                    '${session.expensesInNextMonth.first.name}${session.expensesInNextMonth.length > 1 ? ' ほか${session.expensesInNextMonth.length - 1}件' : ''}',
                    style: text.titleMedium,
                  ),
                  Text(
                    formatYen(session.nextMonthTotalYen),
                    style: text.titleLarge,
                  ),
                  TextButton(
                    onPressed: () => _expenses(context),
                    child: const Text('すべて見る'),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Text('これからの予定費', style: text.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Text('来年', style: text.bodyLarge),
                  Text(
                    formatYen(session.nextYearExpensesTotalYen),
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('5年間', style: text.bodyLarge),
                  Text(
                    formatYen(session.fiveYearExpensesTotalYen),
                    style: text.titleMedium,
                  ),
                ] else if (session.plannedExpenses.isEmpty) ...[
                  Text('予定費はまだありません', style: text.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '車検やタイヤ交換など、これから予定している費用を登録すると、保有目標までのお金の見通しを確認できます。',
                    style: text.bodyLarge,
                  ),
                ] else ...[
                  Text('保有目標までの予定費はありません', style: text.titleLarge),
                  TextButton(
                    onPressed: () => _expenses(context),
                    child: const Text('予定費を確認する'),
                  ),
                ],
              ],
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
              FilledButton(
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
              if (!reached) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: () => _addExpense(context),
                  child: const Text('＋ 予定費を追加'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
