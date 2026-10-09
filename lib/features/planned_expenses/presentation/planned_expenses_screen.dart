import 'package:flutter/material.dart';

import '../../../app/save_request.dart';

import '../../../app/plan_session.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';
import '../../../app/display_format.dart';
import 'planned_expense_editor.dart';

class PlannedExpensesScreen extends StatefulWidget {
  const PlannedExpensesScreen({
    super.key,
    required this.session,
    required this.onChanged,
    required this.onSaveExpense,
    required this.onDeleteExpense,
  });

  final PlanSession session;
  final VoidCallback onChanged;
  final SaveExpenseRequest onSaveExpense;
  final DeleteExpenseRequest onDeleteExpense;

  @override
  State<PlannedExpensesScreen> createState() => _PlannedExpensesScreenState();
}

class _PlannedExpensesScreenState extends State<PlannedExpensesScreen> {
  Future<void> _edit([PlannedExpense? expense]) async {
    final change = await Navigator.of(context).push<ExpenseChange>(
      MaterialPageRoute(
        builder: (_) => PlannedExpenseEditor(
          session: widget.session,
          expense: expense,
          onSave: widget.onSaveExpense,
          onDelete: widget.onDeleteExpense,
        ),
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

  Widget _row(PlannedExpense expense, {bool outside = false}) {
    final text = Theme.of(context).textTheme;
    final reason =
        expense.plannedMonth.compareTo(widget.session.ownershipTargetMonth) > 0
        ? '保有目標より先の予定です'
        : '予定年月が過ぎています';
    return Padding(
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
            children: [
              Text(formatMonth(expense.plannedMonth), style: text.bodyMedium),
              Text(formatYen(expense.amountYen), style: text.titleMedium),
            ],
          ),
          if (outside) Text(reason, style: text.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: ValueKey('edit-expense-${expense.id}'),
            onPressed: () => _edit(expense),
            child: const Text('編集'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final expenses = widget.session.plannedExpenses;
    // Preserve original positions for same-month rows without mutating input.
    final sorted = expenses.indexed.toList()
      ..sort((a, b) {
        final order = a.$2.plannedMonth.compareTo(b.$2.plannedMonth);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
    final years = <int, List<PlannedExpense>>{};
    final outside = <PlannedExpense>[];
    for (final entry in sorted) {
      final expense = entry.$2;
      if (widget.session.isExpenseIncluded(expense)) {
        (years[expense.plannedMonth.year] ??= []).add(expense);
      } else {
        outside.add(expense);
      }
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
              Text('保有目標までの予定費', style: text.titleMedium),
              Text(
                formatYen(widget.session.ownershipTargetExpensesTotalYen),
                key: const ValueKey('included-expenses-total'),
                style: text.headlineMedium,
              ),
              Text('計画外の予定費：${outside.length}件', style: text.bodyMedium),
              Text('${expenses.length}件の予定', style: text.bodyMedium),
              if (expenses.isEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text('予定費はまだありません', style: text.bodyLarge),
                Text('将来予定している車検やタイヤ交換などを登録できます', style: text.bodyMedium),
              ] else if (years.isEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text('保有目標までの予定費はありません', style: text.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => _edit(),
                child: const Text('予定費を追加'),
              ),
              if (years.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                Semantics(
                  header: true,
                  child: Text('計画内の予定費', style: text.titleLarge),
                ),
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
                          children: [
                            Text('${year.key}年', style: text.titleLarge),
                            Text(
                              '合計 ${formatYen(year.value.fold<int>(0, (sum, expense) => sum + expense.amountYen))}',
                              style: text.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      for (final expense in year.value) _row(expense),
                    ],
                  ),
                ),
              if (outside.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                Semantics(
                  header: true,
                  child: Text('計画外の予定費', style: text.titleLarge),
                ),
                for (final expense in outside) _row(expense, outside: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
