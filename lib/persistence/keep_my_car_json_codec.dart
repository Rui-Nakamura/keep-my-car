import 'dart:convert';

import 'keep_my_car_data_dto.dart';
import 'storage_format.dart';

/// JSON syntax, required fields, types and version; never constructs domain
/// models. Strings can be transported as UTF-8 using dart:convert's utf8 codec.
/// Invalid storage input throws FormatException, without partial results.
class KeepMyCarJsonCodec {
  const KeepMyCarJsonCodec();

  String encode(KeepMyCarDataDto data) {
    validateStorageFormat(data);
    final car = data.car;
    final plan = data.planConditions;
    return jsonEncode({
      'formatVersion': data.formatVersion,
      'ownerBirthMonth': data.ownerBirthMonth,
      'car': {
        'name': car.name,
        'firstRegistrationMonth': car.firstRegistrationMonth,
        'currentMileageKm': car.currentMileageKm,
        'mileageCheckedMonth': car.mileageCheckedMonth,
        'annualMileageKm': car.annualMileageKm,
      },
      'planConditions': {
        'currentMileageKm': plan.currentMileageKm,
        'annualMileageKm': plan.annualMileageKm,
        'ownershipTargetAge': plan.ownershipTargetAge,
        'currentCarFundYen': plan.currentCarFundYen,
        'reserveTargetAge': plan.reserveTargetAge,
        'largeRepairReserveYen': plan.largeRepairReserveYen,
      },
      // Preserve list order for existing same-month display tie-breaking.
      // Identity is the ID; this codec assigns no business meaning to position.
      'plannedExpenses': [
        for (final expense in data.plannedExpenses)
          {
            'id': expense.id,
            'name': expense.name,
            'amountYen': expense.amountYen,
            'plannedMonth': expense.plannedMonth,
            'basis': expense.basis,
            'memo': expense.memo,
            'status': expense.status,
          },
      ],
    });
  }

  KeepMyCarDataDto decode(String source) {
    final root = _object(jsonDecode(source), 'root');
    final version = _field<int>(root, 'formatVersion');
    if (version != 1) {
      throw FormatException('Unsupported formatVersion: $version');
    }
    final car = _object(root['car'], 'car');
    final plan = _object(root['planConditions'], 'planConditions');
    final expenses = _field<List<dynamic>>(root, 'plannedExpenses');
    final data = KeepMyCarDataDto(
      formatVersion: version,
      ownerBirthMonth: _field<String>(root, 'ownerBirthMonth'),
      car: CarDto(
        name: _field<String>(car, 'name'),
        firstRegistrationMonth: _field<String>(car, 'firstRegistrationMonth'),
        currentMileageKm: _field<int>(car, 'currentMileageKm'),
        mileageCheckedMonth: _field<String>(car, 'mileageCheckedMonth'),
        annualMileageKm: _field<int>(car, 'annualMileageKm'),
      ),
      planConditions: PlanConditionsDto(
        currentMileageKm: _field<int>(plan, 'currentMileageKm'),
        annualMileageKm: _field<int>(plan, 'annualMileageKm'),
        ownershipTargetAge: _field<int>(plan, 'ownershipTargetAge'),
        currentCarFundYen: _field<int>(plan, 'currentCarFundYen'),
        reserveTargetAge: _field<int>(plan, 'reserveTargetAge'),
        largeRepairReserveYen: _field<int>(plan, 'largeRepairReserveYen'),
      ),
      plannedExpenses: [
        for (var i = 0; i < expenses.length; i++)
          _expense(_object(expenses[i], 'plannedExpenses[$i]')),
      ],
    );
    validateStorageFormat(data);
    return data;
  }

  PlannedExpenseDto _expense(Map<String, dynamic> value) {
    if (!value.containsKey('memo') ||
        (value['memo'] != null && value['memo'] is! String)) {
      throw const FormatException('Expected memo as string or null');
    }
    return PlannedExpenseDto(
      id: _field<int>(value, 'id'),
      name: _field<String>(value, 'name'),
      amountYen: _field<int>(value, 'amountYen'),
      plannedMonth: _field<String>(value, 'plannedMonth'),
      basis: _field<String>(value, 'basis'),
      memo: value['memo'] as String?,
      status: _field<String>(value, 'status'),
    );
  }

  Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected object: $field');
    }
    return value;
  }

  T _field<T>(Map<String, dynamic> object, String key) {
    final value = object[key];
    if (value is! T) throw FormatException('Expected $T: $key');
    return value;
  }
}
