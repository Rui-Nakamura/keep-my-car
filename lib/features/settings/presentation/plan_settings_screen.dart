import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/save_request.dart';
import '../../../app/save_restriction.dart';
import '../../../app/save_progress.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/models/year_month.dart';
import '../../../domain/plan_conditions_validation.dart';
import '../../../app/display_format.dart';

class PlanSettingsScreen extends StatefulWidget {
  const PlanSettingsScreen({
    super.key,
    required this.conditions,
    required this.birthMonth,
    required this.referenceMonth,
    required this.onApply,
    this.onDataManagement,
    this.onFundingPlan,
    this.fundingStatusText,
  });
  final PlanConditions conditions;
  final Future<void> Function()? onFundingPlan;
  final String Function()? fundingStatusText;
  final VoidCallback? onDataManagement;
  final YearMonth birthMonth;
  final YearMonth referenceMonth;
  final FutureOr<Map<PlanField, PlanInputError>> Function(PlanConditions)
  onApply;

  @override
  State<PlanSettingsScreen> createState() => _PlanSettingsScreenState();
}

class _PlanSettingsScreenState extends State<PlanSettingsScreen> {
  final _controllers = <PlanField, TextEditingController>{};
  final _focus = <PlanField, FocusNode>{};
  final _errors = <PlanField, String>{};
  late int _ownershipAge;

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final initial = widget.conditions;
    _ownershipAge = initial.ownershipTargetAge;

    final values = {
      PlanField.currentMileage: initial.currentMileageKm,
      PlanField.annualMileage: initial.annualMileageKm,
    };
    for (final entry in values.entries) {
      final controller = TextEditingController(text: formatNumber(entry.value));
      final focus = FocusNode();
      _controllers[entry.key] = controller;
      _focus[entry.key] = focus;
      focus.addListener(() {
        if (!mounted) return;
        final parsed = _parse(controller.text);
        if (parsed != null) {
          controller.text = focus.hasFocus ? '$parsed' : formatNumber(parsed);
        }
        if (!focus.hasFocus) {
          final errors = _validate();
          setState(() {
            _errors.remove(entry.key);
            if (errors[entry.key] case final error?) _errors[entry.key] = error;
          });
        }
      });
    }
  }

  int? _parse(String text) {
    if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$').hasMatch(text)) {
      return null;
    }
    return int.tryParse(text.replaceAll(',', ''));
  }

  PlanConditions _candidate() => PlanConditions(
    fundingPlanEnabled: widget.conditions.fundingPlanEnabled,
    currentMileageKm:
        _parse(_controllers[PlanField.currentMileage]!.text) ??
        widget.conditions.currentMileageKm,
    annualMileageKm:
        _parse(_controllers[PlanField.annualMileage]!.text) ??
        widget.conditions.annualMileageKm,
    ownershipTargetAge: _ownershipAge,
    currentCarFundYen: widget.conditions.currentCarFundYen,
    reserveTargetAge: widget.conditions.reserveTargetAge,
    largeRepairReserveYen: widget.conditions.largeRepairReserveYen,
  );

  String _domainMessage(PlanField field, PlanInputError error) {
    if (error == PlanInputError.pastTargetMonth) {
      return '備え目標の誕生月が基準月より前です。基準月以降になる年齢を選んでください。';
    }
    if (error == PlanInputError.exceedsOwnershipAge) {
      return '備え目標年齢は保有目標年齢以下にしてください。';
    }
    return switch (field) {
      PlanField.currentMileage => '0〜2,000,000の整数を入力してください。',
      PlanField.annualMileage => '0〜200,000の整数を入力してください。',
      PlanField.fund || PlanField.reserve => '0〜1,000,000,000の整数を入力してください。',
      PlanField.ownershipAge => '現在年齢以上、100歳以下の年齢を選んでください。',
      PlanField.reserveAge => '基準月以降で、保有目標年齢以下の年齢を選んでください。',
    };
  }

  Map<PlanField, String> _validate() {
    final errors = validateBasicPlanConditions(
      _candidate(),
      birthMonth: widget.birthMonth,
      referenceMonth: widget.referenceMonth,
    ).map((field, error) => MapEntry(field, _domainMessage(field, error)));
    for (final entry in _controllers.entries) {
      if (entry.value.text.isEmpty) {
        errors[entry.key] = '入力してください。0も入力できます。';
      } else if (_parse(entry.value.text) == null) {
        errors[entry.key] = '0以上の整数を入力してください。小数や文字は使用できません。';
      }
    }
    return errors;
  }

  Future<void> _apply() async {
    if (_saving || SaveRestriction.of(context)) return;
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final rejected = await widget.onApply(_candidate());
      if (!mounted) return;
      if (rejected.isNotEmpty) {
        setState(() {
          _errors.addAll(
            rejected.map(
              (field, error) => MapEntry(field, _domainMessage(field, error)),
            ),
          );
        });
        return;
      }
      Navigator.of(context).pop();
    } on SaveRequestFailure catch (error) {
      if (mounted && !error.uncertain) {
        setState(() => _saveError = SaveRequestFailure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseAge() async {
    FocusScope.of(context).unfocus();
    final minimum = completedYears(widget.birthMonth, widget.referenceMonth);
    final ages = [for (var age = minimum; age <= 100; age++) age];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('保有目標年齢'),
        children: [
          if (ages.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('選択できる年齢がありません。保有目標年齢を確認してください。'),
            ),
          for (final age in ages)
            SimpleDialogOption(
              key: ValueKey('age-option-$age'),
              onPressed: () => Navigator.of(context).pop(age),
              child: Text('$age歳'),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _ownershipAge = selected;
      final errors = _validate();
      for (final field in [PlanField.ownershipAge]) {
        _errors.remove(field);
        if (errors[field] case final error?) _errors[field] = error;
      }
    });
  }

  Future<void> _openFunding() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final dirty =
        _controllers.entries.any(
          (entry) =>
              _parse(entry.value.text) !=
              (entry.key == PlanField.currentMileage
                  ? widget.conditions.currentMileageKm
                  : widget.conditions.annualMileageKm),
        ) ||
        _ownershipAge != widget.conditions.ownershipTargetAge;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('変更を破棄して移動しますか？'),
          content: const Text('基本計画の未保存の変更は保存されません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('変更を破棄して移動'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
      setState(() {
        _controllers[PlanField.currentMileage]!.text = formatNumber(
          widget.conditions.currentMileageKm,
        );
        _controllers[PlanField.annualMileage]!.text = formatNumber(
          widget.conditions.annualMileageKm,
        );
        _ownershipAge = widget.conditions.ownershipTargetAge;
        _errors.clear();
      });
    }
    await widget.onFundingPlan!();
    if (mounted) setState(() {});
  }

  Widget _error(PlanField field) => _errors[field] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            _errors[field]!,
            key: ValueKey('error-${field.name}'),
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: Theme.of(context).colorScheme.error),
          ),
        );

  Widget _number(PlanField field, String label, String unit) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: label,
          child: TextField(
            key: ValueKey('input-${field.name}'),
            controller: _controllers[field],
            focusNode: _focus[field],
            keyboardType: TextInputType.number,
            minLines: 1,
            maxLines: null,
            scrollPadding: const EdgeInsets.all(32),
            decoration: const InputDecoration(),
          ),
        ),
        Text(unit, style: Theme.of(context).textTheme.bodyMedium),
        _error(field),
      ],
    ),
  );

  Widget _age() {
    const field = PlanField.ownershipAge;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('保有目標年齢', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: ValueKey('input-${field.name}'),
            onPressed: _chooseAge,
            child: Text('$_ownershipAge歳'),
          ),
          _error(field),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final focus in _focus.values) {
      focus.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SaveProgress(
    saving: _saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('計画設定')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('車・所有計画', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: AppSpacing.xl),
              _number(PlanField.currentMileage, '現在走行距離', 'km'),
              _number(PlanField.annualMileage, '年間走行距離', 'km / 年'),
              _age(),
              if (_saveError != null)
                Text(_saveError!, key: const ValueKey('save-error')),
              FilledButton(
                key: const ValueKey('apply-plan'),
                onPressed: _saving || SaveRestriction.of(context)
                    ? null
                    : _apply,
                child: Text(_saving ? '保存中…' : 'この試算に反映'),
              ),
              if (widget.onFundingPlan != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(widget.fundingStatusText?.call() ?? ''),
                OutlinedButton(
                  key: const ValueKey('open-funding-plan'),
                  onPressed: _saving ? null : _openFunding,
                  child: const Text('資金計画（任意）'),
                ),
              ],
              if (widget.onDataManagement != null) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: _saving ? null : widget.onDataManagement,
                  child: const Text('データ管理'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
