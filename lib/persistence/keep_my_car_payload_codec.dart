import 'keep_my_car_data_dto.dart';
import 'storage_format.dart';

/// Converts formal input fields between objects and existing DTOs.
/// Checks required fields and JSON types; ignores unknown fields.
/// Envelope callers explicitly select the schema version; payloads contain no
/// version metadata. Mapper validates domain rules after structural decoding.
class KeepMyCarPayloadCodec {
  const KeepMyCarPayloadCodec();

  Map<String, dynamic> encode(KeepMyCarDataDto data, {int? version}) {
    validateStorageFormat(data);
    final outputVersion = version ?? data.formatVersion;
    if (outputVersion < 1 || outputVersion > data.formatVersion) {
      throw FormatException(
        'Unsupported payload output version: $outputVersion',
      );
    }
    final car = data.car;
    final plan = data.planConditions;
    return {
      if (outputVersion >= 3) 'photoId': data.photoId,
      'ownerBirthMonth': data.ownerBirthMonth,
      'car': {
        'name': car.name,
        'firstRegistrationMonth': car.firstRegistrationMonth,
        'currentMileageKm': car.currentMileageKm,
        'mileageCheckedMonth': car.mileageCheckedMonth,
        'annualMileageKm': car.annualMileageKm,
      },
      'planConditions': {
        if (outputVersion >= 2) 'fundingPlanEnabled': plan.fundingPlanEnabled,
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
    };
  }

  KeepMyCarDataDto decode(Map<String, dynamic> root, {required int version}) {
    final car = _object(root['car'], 'car');
    final plan = _object(root['planConditions'], 'planConditions');
    final expenses = _field<List<dynamic>>(root, 'plannedExpenses');
    if (version >= 3 &&
        (!root.containsKey('photoId') ||
            (root['photoId'] != null && root['photoId'] is! String))) {
      throw const FormatException('Required photoId as string or null');
    }
    final photoId = version >= 3 ? root['photoId'] as String? : null;
    if (version >= 3) validatePhotoId(photoId);
    return KeepMyCarDataDto(
      photoId: photoId,
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
        fundingPlanEnabled: version == 1
            ? null
            : _field<bool>(plan, 'fundingPlanEnabled'),
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
