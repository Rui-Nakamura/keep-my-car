import 'package:flutter/material.dart';

import '../../../app/plan_session.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';
import '../../../domain/models/year_month.dart';
import '../../../domain/planned_expense_validation.dart';
import '../../home/presentation/home_format.dart';

class PlannedExpenseEditor extends StatefulWidget {
  const PlannedExpenseEditor({super.key, required this.session, this.expense});

  final PlanSession session;
  final PlannedExpense? expense;

  @override
  State<PlannedExpenseEditor> createState() => _PlannedExpenseEditorState();
}

class _PlannedExpenseEditorState extends State<PlannedExpenseEditor> {
  late final _name = TextEditingController(text: widget.expense?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : '${widget.expense!.amountYen}',
  );
  late YearMonth _month =
      widget.expense?.plannedMonth ?? widget.session.referenceMonth;
  Map<ExpenseField, ExpenseInputError> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    FocusScope.of(context).unfocus();
    final errors = validatePlannedExpense(
      name: _name.text,
      month: _month,
      amount: _amount.text,
      referenceMonth: widget.session.referenceMonth,
      ownershipTargetMonth: widget.session.ownershipTargetMonth,
    );
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final change = widget.session.saveExpense(
      id: widget.expense?.id,
      name: _name.text,
      month: _month,
      amountYen: int.parse(_amount.text),
    );
    Navigator.of(context).pop(change);
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('この予定費を削除しますか？'),
        content: Text(widget.expense!.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const ValueKey('confirm-delete-expense'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    Navigator.of(context).pop(widget.session.deleteExpense(widget.expense!.id));
  }

  Future<void> _chooseMonth() async {
    FocusScope.of(context).unfocus();
    final start = widget.session.referenceMonth;
    final end = widget.session.ownershipTargetMonth;
    final year = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('予定年を選択'),
        children: [
          for (var year = start.year; year <= end.year; year++)
            SimpleDialogOption(
              key: ValueKey('expense-year-$year'),
              onPressed: () => Navigator.pop(context, year),
              child: Text('$year年'),
            ),
        ],
      ),
    );
    if (!mounted || year == null) return;
    final month = await showDialog<YearMonth>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('$year年の予定月を選択'),
        children: [
          for (var month = 1; month <= 12; month++)
            if (isExpenseMonthInRange(
              YearMonth(year, month),
              referenceMonth: start,
              ownershipTargetMonth: end,
            ))
              SimpleDialogOption(
                key: ValueKey('expense-month-$month'),
                onPressed: () => Navigator.pop(context, YearMonth(year, month)),
                child: Text('$month月'),
              ),
        ],
      ),
    );
    if (!mounted || month == null) return;
    setState(() {
      _month = month;
      _errors.remove(ExpenseField.month);
    });
  }

  Widget _error(ExpenseField field) {
    final error = _errors[field];
    if (error == null) return const SizedBox.shrink();
    final message = switch (field) {
      ExpenseField.name =>
        error == ExpenseInputError.required
            ? '項目名を入力してください。'
            : '項目名は40文字以内で入力してください。',
      ExpenseField.month => '予定年月を基準月から現在の保有目標年月までの範囲に戻してください。',
      ExpenseField.amount =>
        error == ExpenseInputError.required
            ? '金額を入力してください。0円も登録できます。'
            : '金額は0〜1,000,000,000円の整数で入力してください。',
    };
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        key: ValueKey('expense-error-${field.name}'),
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _input(
    ExpenseField field,
    String label,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Semantics(
        label: label,
        child: TextField(
          key: ValueKey('expense-input-${field.name}'),
          controller: controller,
          keyboardType: field == ExpenseField.amount
              ? TextInputType.number
              : TextInputType.text,
          minLines: 1,
          maxLines: null,
          scrollPadding: const EdgeInsets.all(32),
        ),
      ),
      _error(field),
      const SizedBox(height: AppSpacing.xl),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final title = widget.expense == null ? '予定費を追加' : '予定費を編集';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Keep the full title readable even when the AppBar is constrained.
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: AppSpacing.xl),
              _input(ExpenseField.name, '項目名', _name),
              Text('予定年月', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const ValueKey('expense-input-month'),
                onPressed: _chooseMonth,
                child: Text(formatMonth(_month)),
              ),
              Text(
                '${formatMonth(widget.session.referenceMonth)}〜${formatMonth(widget.session.ownershipTargetMonth)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              _error(ExpenseField.month),
              const SizedBox(height: AppSpacing.xl),
              _input(ExpenseField.amount, '金額（円）', _amount),
              FilledButton(
                key: const ValueKey('save-expense'),
                onPressed: _save,
                child: Text(widget.expense == null ? '追加' : '保存'),
              ),
              if (widget.expense != null) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: _delete,
                  child: const Text('この予定を削除'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
