import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/display_format.dart';
import '../../../app/plan_session.dart';
import '../../../app/save_progress.dart';
import '../../../app/save_request.dart';
import '../../../app/save_restriction.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/major_repair_reserve.dart';
import '../../../domain/models/ownership_goal.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/plan_conditions_validation.dart';
import '../../repair_reserve/presentation/repair_reserve_screen.dart';

String fundingStatusText(FundingPlanStatus status) => switch (status) {
  FundingPlanStatus.unused => '資金計画は利用していません',
  FundingPlanStatus.needsReview => '資金計画の設定を確認してください',
  FundingPlanStatus.calculable => '資金計画を利用しています',
  FundingPlanStatus.calculationFailed => '現在の条件では計算できません',
};

class FundingPlanScreen extends StatefulWidget {
  const FundingPlanScreen({
    super.key,
    required this.session,
    required this.onApply,
    required this.onViewed,
  });
  final PlanSession session;
  final FutureOr<Map<PlanField, PlanInputError>> Function(PlanConditions)
  onApply;
  final VoidCallback onViewed;
  @override
  State<FundingPlanScreen> createState() => _FundingPlanScreenState();
}

class _FundingPlanScreenState extends State<FundingPlanScreen> {
  final _fund = TextEditingController();
  final _amount = TextEditingController();
  int? _age;
  bool _editing = false;
  bool _saving = false;
  String? _saveError;
  final _errors = <PlanField, String>{};
  PlanSession get plan => widget.session;

  // Display choice only: never infer usage history or change retained values.
  bool get _ageUnselected =>
      !plan.conditions.fundingPlanEnabled &&
      plan.conditions.reserveTargetAge == 0;

  @override
  void initState() {
    super.initState();
    _reset();
    _editing = plan.conditions.fundingPlanEnabled;
  }

  void _reset() {
    _fund.text = formatNumber(plan.conditions.currentCarFundYen);
    _amount.text = formatNumber(plan.conditions.largeRepairReserveYen);
    _age = _ageUnselected ? null : plan.conditions.reserveTargetAge;
    _errors.clear();
    _saveError = null;
  }

  int? _parse(String value) =>
      RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$').hasMatch(value)
      ? int.tryParse(value.replaceAll(',', ''))
      : null;

  PlanConditions _candidate(bool enabled) => PlanConditions(
    fundingPlanEnabled: enabled,
    currentMileageKm: plan.conditions.currentMileageKm,
    annualMileageKm: plan.conditions.annualMileageKm,
    ownershipTargetAge: plan.conditions.ownershipTargetAge,
    currentCarFundYen: _parse(_fund.text) ?? plan.conditions.currentCarFundYen,
    reserveTargetAge: _age ?? plan.conditions.reserveTargetAge,
    largeRepairReserveYen:
        _parse(_amount.text) ?? plan.conditions.largeRepairReserveYen,
  );

  String _message(PlanField field, PlanInputError error) => switch (error) {
    PlanInputError.pastTargetMonth => '備える年齢の誕生月が基準月より前です。基準月以降の年齢を選んでください。',
    PlanInputError.exceedsOwnershipAge => '備える年齢は保有目標年齢以下にしてください。',
    PlanInputError.outOfRange =>
      field == PlanField.reserveAge
          ? '年齢は0〜100歳の範囲で選択してください。'
          : '金額は0〜1,000,000,000円の整数で入力してください。',
  };

  Future<void> _save({bool enabled = true}) async {
    if (_saving || SaveRestriction.of(context)) return;
    FocusScope.of(context).unfocus();
    _errors.clear();
    final next = _candidate(enabled);
    if (enabled) {
      _errors.addAll(
        validateFundingPlanConditions(
          next,
          birthMonth: plan.birthMonth,
          referenceMonth: plan.referenceMonth,
        ).map((field, error) => MapEntry(field, _message(field, error))),
      );
      if (_age == null) _errors[PlanField.reserveAge] = '年齢を選択してください。';
      for (final entry in {
        PlanField.fund: _fund,
        PlanField.reserve: _amount,
      }.entries) {
        if (_parse(entry.value.text) == null) {
          _errors[entry.key] = '0以上の整数を入力してください。0円も入力できます。';
        }
      }
    }
    setState(() {});
    if (_errors.isNotEmpty) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final errors = await widget.onApply(next);
      if (!mounted) return;
      if (errors.isNotEmpty) {
        setState(
          () => _errors.addAll(
            errors.map(
              (field, error) => MapEntry(field, _message(field, error)),
            ),
          ),
        );
        return;
      }
      setState(() {
        _editing = enabled;
        _reset();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? '資金計画を保存しました' : '資金計画を使わない設定にしました')),
      );
    } on SaveRequestFailure catch (error) {
      if (mounted && !error.uncertain) {
        setState(() => _saveError = SaveRequestFailure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stop() async {
    if (_saving || SaveRestriction.of(context)) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('資金計画を使わない設定にしますか？'),
        content: const Text(
          '設定した金額や年齢は残ります。いつでも再開できます。愛車の予定費や未来タイムラインには影響しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('資金計画を使わない'),
          ),
        ],
      ),
    );
    if (mounted && accepted == true) await _save(enabled: false);
  }

  Future<void> _chooseAge() async {
    FocusScope.of(context).unfocus();
    // Use the shared validator for candidates, including same-month boundaries.
    final ages = [
      for (var age = 0; age <= 100; age++)
        if (!validateFundingPlanConditions(
          PlanConditions(
            fundingPlanEnabled: true,
            currentMileageKm: plan.conditions.currentMileageKm,
            annualMileageKm: plan.conditions.annualMileageKm,
            ownershipTargetAge: plan.conditions.ownershipTargetAge,
            currentCarFundYen: 0,
            reserveTargetAge: age,
            largeRepairReserveYen: 0,
          ),
          birthMonth: plan.birthMonth,
          referenceMonth: plan.referenceMonth,
        ).containsKey(PlanField.reserveAge))
          age,
    ];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('大きな修理に備える年齢'),
        children: [
          if (ages.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('選択できる年齢がありません。保有目標年齢を確認してください。'),
            ),
          for (final age in ages)
            SimpleDialogOption(
              key: ValueKey('age-option-$age'),
              onPressed: () => Navigator.pop(context, age),
              child: Text('$age歳'),
            ),
        ],
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        _age = selected;
        _errors.remove(PlanField.reserveAge);
      });
    }
  }

  Future<void> _result() async {
    if (_saving) return;
    final c = plan.conditions;
    final screen = RepairReserveScreen(
      ownershipGoal: OwnershipGoal(targetAge: c.ownershipTargetAge),
      reserve: MajorRepairReserve(
        targetAge: c.reserveTargetAge,
        amountYen: c.largeRepairReserveYen,
      ),
      result: plan.reserveResult,
      updatePending: plan.reservePending,
      deltaYen: plan.reserveDeltaYen,
      onViewed: widget.onViewed,
      onReviewSettings: () => Navigator.of(context).pop(),
    );
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  Widget _error(PlanField field) => _errors[field] == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Text(
            _errors[field]!,
            key: ValueKey('error-${field.name}'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );

  Widget _number(
    PlanField field,
    String label,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Semantics(
        label: label,
        child: TextField(
          key: ValueKey('input-${field.name}'),
          controller: controller,
          keyboardType: TextInputType.number,
          maxLines: null,
          scrollPadding: const EdgeInsets.all(32),
        ),
      ),
      const Text('円'),
      _error(field),
      const SizedBox(height: AppSpacing.xl),
    ],
  );

  @override
  void dispose() {
    _fund.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = plan.conditions.fundingPlanEnabled;
    final restricted = SaveRestriction.of(context);
    return SaveProgress(
      saving: _saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('資金計画')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '資金計画（任意）',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  fundingStatusText(plan.fundingPlanStatus),
                  key: const ValueKey('funding-status'),
                ),
                if (!_editing) ...[
                  ...[
                    Text(
                      '現在の愛車資金：${formatYen(plan.conditions.currentCarFundYen)}',
                    ),
                    Text(
                      _ageUnselected
                          ? '大きな修理に備える年齢：選択してください'
                          : '大きな修理に備える年齢：${plan.conditions.reserveTargetAge}歳',
                    ),
                    Text(
                      '大きな修理に備える金額：${formatYen(plan.conditions.largeRepairReserveYen)}',
                    ),
                  ],
                  FilledButton(
                    key: const ValueKey('start-funding'),
                    onPressed: restricted
                        ? null
                        : () => setState(() {
                            _reset();
                            _editing = true;
                          }),
                    child: const Text('資金計画を設定する'),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.xl),
                  _number(PlanField.fund, '現在の愛車資金', _fund),
                  Text(
                    '大きな修理に備える年齢',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Semantics(
                    label: '大きな修理に備える年齢',
                    value: _age == null ? '選択してください' : '$_age歳',
                    button: true,
                    enabled: !restricted,
                    onTap: restricted ? null : _chooseAge,
                    excludeSemantics: true,
                    child: OutlinedButton(
                      key: const ValueKey('input-reserveAge'),
                      onPressed: restricted ? null : _chooseAge,
                      child: Text(_age == null ? '選択してください' : '$_age歳'),
                    ),
                  ),
                  _error(PlanField.reserveAge),
                  const SizedBox(height: AppSpacing.xl),
                  _number(PlanField.reserve, '大きな修理に備える金額', _amount),
                  const Text('将来の大きな修理などに備えて、確保しておきたい金額です。'),
                  if (_saveError != null)
                    Text(_saveError!, key: const ValueKey('save-error')),
                  FilledButton(
                    key: const ValueKey('save-funding'),
                    onPressed: restricted || _saving ? null : () => _save(),
                    child: Text(
                      _saving
                          ? '保存中…'
                          : enabled
                          ? '保存'
                          : '保存して利用する',
                    ),
                  ),
                  if (!enabled)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _editing = false;
                              _reset();
                            }),
                      child: const Text('キャンセル'),
                    ),
                ],
                if (enabled) ...[
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton(
                    onPressed: _saving ? null : _result,
                    child: const Text('計算結果を確認する'),
                  ),
                  TextButton(
                    onPressed: restricted || _saving ? null : _stop,
                    child: const Text('資金計画を使わない'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
