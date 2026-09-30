import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/save_progress.dart';
import '../../../app/save_request.dart';
import '../../../domain/car_validation.dart';
import '../../../domain/models/car.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/models/year_month.dart';
import '../../../domain/plan_conditions_validation.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({
    super.key,
    required this.referenceMonth,
    required this.onSave,
  });
  final YearMonth referenceMonth;
  final Future<void> Function({
    required YearMonth ownerBirthMonth,
    required Car car,
    required PlanConditions conditions,
  })
  onSave;
  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  static const labels = {
    'birth': '生年月',
    'name': '愛車名',
    'registration': '初度登録年月',
    'mileage': '現在走行距離（km）',
    'checked': '走行距離確認年月',
    'annual': '年間走行距離（km）',
    'ownership': '保有目標年齢（歳）',
    'fund': '現在の愛車専用資金（円）',
    'reserveAge': '大型修理への備え目標年齢（歳）',
    'reserve': '大型修理予備費（円）',
  };
  late final controllers = {
    for (final key in labels.keys)
      key: TextEditingController(
        text: key == 'checked'
            ? widget.referenceMonth.toString()
            : key == 'fund' || key == 'reserve'
            ? '0'
            : '',
      ),
  };
  final errors = <String, String>{};
  bool saving = false;
  String? saveError;
  YearMonth? month(String key) {
    final value = controllers[key]!.text;
    if (value.length != 7 ||
        !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
      return null;
    }
    return YearMonth(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5)),
    );
  }

  int? number(String key) {
    final value = controllers[key]!.text;
    return RegExp(r'^[0-9]+$').hasMatch(value) ? int.tryParse(value) : null;
  }

  Future<void> save() async {
    if (saving) return;
    FocusScope.of(context).unfocus();
    errors.clear();
    for (final key in ['birth', 'registration', 'checked']) {
      if (month(key) == null) errors[key] = '年月を入力してください（例：1970-04）。';
    }
    final name = validateCarName(controllers['name']!.text);
    if (name.error != null) errors['name'] = '愛車名を改行やタブを含めず40文字以内で入力してください。';
    const fields = {
      'mileage': PlanField.currentMileage,
      'annual': PlanField.annualMileage,
      'ownership': PlanField.ownershipAge,
      'fund': PlanField.fund,
      'reserveAge': PlanField.reserveAge,
      'reserve': PlanField.reserve,
    };
    for (final key in fields.keys) {
      if (number(key) == null) errors[key] = '0以上の整数を入力してください。';
    }
    PlanConditions? plan;
    if (month('birth') != null &&
        fields.keys.every((key) => number(key) != null)) {
      plan = PlanConditions(
        currentMileageKm: number('mileage')!,
        annualMileageKm: number('annual')!,
        ownershipTargetAge: number('ownership')!,
        currentCarFundYen: number('fund')!,
        reserveTargetAge: number('reserveAge')!,
        largeRepairReserveYen: number('reserve')!,
      );
      final rejected = validatePlanConditions(
        plan,
        birthMonth: month('birth')!,
        referenceMonth: widget.referenceMonth,
      );
      for (final entry in fields.entries) {
        final error = rejected[entry.value];
        if (error != null) {
          errors[entry.key] = error == PlanInputError.pastTargetMonth
              ? '備え目標の誕生月が現在月以降になる年齢を入力してください。'
              : error == PlanInputError.exceedsOwnershipAge
              ? '備え目標年齢は保有目標年齢以下にしてください。'
              : switch (entry.value) {
                  PlanField.currentMileage => '0〜2,000,000kmで入力してください。',
                  PlanField.annualMileage => '0〜200,000kmで入力してください。',
                  PlanField.fund ||
                  PlanField.reserve => '0〜1,000,000,000円で入力してください。',
                  _ => '現在年齢以上、100歳以下の年齢を入力してください。',
                };
        }
      }
    }
    setState(() => saveError = null);
    if (errors.isNotEmpty || plan == null) return;
    final car = Car(
      name: name.name,
      firstRegistrationMonth: month('registration')!,
      currentMileageKm: plan.currentMileageKm,
      mileageCheckedMonth: month('checked')!,
      annualMileageKm: plan.annualMileageKm,
    );
    setState(() => saving = true);
    try {
      await widget.onSave(
        ownerBirthMonth: month('birth')!,
        car: car,
        conditions: plan,
      );
    } on SaveRequestFailure catch (error) {
      if (mounted && !error.uncertain) {
        setState(() => saveError = SaveRequestFailure.message);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget input(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(labels[key]!, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey('setup-$key'),
          controller: controllers[key],
          minLines: 1,
          maxLines: null,
          scrollPadding: const EdgeInsets.all(32),
          keyboardType: key == 'name'
              ? TextInputType.text
              : ['birth', 'registration', 'checked'].contains(key)
              ? TextInputType.datetime
              : TextInputType.number,
          inputFormatters: key == 'name'
              ? [FilteringTextInputFormatter.deny(RegExp(r'[\r\n\t]'))]
              : null,
        ),
        if (['birth', 'registration', 'checked'].contains(key))
          const Text('年と月を入力（例：1970-04）'),
        if (errors[key] != null)
          Text(
            errors[key]!,
            key: ValueKey('setup-error-$key'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SaveProgress(
    saving: saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('初期設定')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in {
                'あなたについて': ['birth'],
                '愛車について': [
                  'name',
                  'registration',
                  'mileage',
                  'checked',
                  'annual',
                ],
                'これからの計画': ['ownership', 'fund', 'reserveAge', 'reserve'],
              }.entries) ...[
                Text(
                  section.key,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 24),
                for (final key in section.value) input(key),
              ],
              if (saveError != null)
                Text(saveError!, key: const ValueKey('save-error')),
              FilledButton(
                key: const ValueKey('setup-save'),
                onPressed: saving ? null : save,
                child: Text(saving ? '保存中…' : 'この内容で始める'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
