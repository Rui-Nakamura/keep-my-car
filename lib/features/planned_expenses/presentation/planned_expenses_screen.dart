import 'package:flutter/material.dart';

import '../../../app/plan_session.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';
import '../../home/presentation/home_format.dart';
import 'planned_expense_editor.dart';

class PlannedExpensesScreen extends StatefulWidget {
  const PlannedExpensesScreen({
    super.key,
    required this.session,
    required this.onChanged,
  });

  final PlanSession session;
  final VoidCallback onChanged;

  @override
  State<PlannedExpensesScreen> createState() => _PlannedExpensesScreenState();
}

class _PlannedExpensesScreenState extends State<PlannedExpensesScreen> {
  Future<void> _edit([PlannedExpense? expense]) async {
    final change = await Navigator.of(context).push<ExpenseChange>(
      MaterialPageRoute(
        builder: (_) =>
            PlannedExpenseEditor(session: widget.session, expense: expense),
      ),
    );
    if (!mounted || change == null || change == ExpenseChange.unchanged) return;
    setState(() {});
    widget.onChanged();
    final message = switch (change) {
      ExpenseChange.added => '予定費を追加しました',
      ExpenseChange.updated => '予定費を更新しました',
      ExpenseChange.deleted => '予定費を削除しました',
      ExpenseChange.unchanged => '',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _yearTotal(List<PlannedExpense> expenses) {
    final included = expenses.where(widget.session.isExpenseIncluded);
    return included.isEmpty
        ? '現在の試算対象なし'
        : '合計 ${formatYen(included.fold<int>(0, (sum, expense) => sum + expense.amountYen))}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plannedExpenses = widget.session.plannedExpenses;
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
                Text('予定費はまだありません', style: text.bodyLarge),
                Text('将来予定している車検やタイヤ交換などを登録できます', style: text.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => _edit(),
                child: const Text('予定費を追加'),
              ),
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
                              _yearTotal(year.value),
                              style: text.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      for (final expense in year.value)
                        Padding(
                          key: ValueKey('expense-${expense.id}'),
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
                              if (!widget.session.isExpenseIncluded(expense))
                                Text('現在の保有期間外', style: text.bodyMedium),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton(
                                key: ValueKey('edit-expense-${expense.id}'),
                                onPressed: () => _edit(expense),
                                child: const Text('編集'),
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
