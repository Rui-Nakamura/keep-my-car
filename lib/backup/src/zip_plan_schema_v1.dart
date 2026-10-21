import 'dart:convert';
import 'dart:typed_data';

import '../../persistence/keep_my_car_data_mapper.dart';
import '../../persistence/keep_my_car_payload_codec.dart';
import 'strict_backup_json.dart';

/// External Plan v1 -> existing payload rules v2, explicitly pinned.
/// The external field allowlists are independent of internal persistence.
class ZipPlanSchemaV1 {
  const ZipPlanSchemaV1();
  static const _payloadRules = 2;
  static const _payload = KeepMyCarPayloadCodec();
  static const _mapper = KeepMyCarDataMapper();

  Uint8List encode(RestoredCarData plan) {
    final dto = _mapper.toDto(
      photoId: null,
      ownerBirthMonth: plan.ownerBirthMonth,
      car: plan.car,
      planConditions: plan.planConditions,
      plannedExpenses: plan.plannedExpenses,
    );
    final root = _payload.encode(dto, version: _payloadRules);
    _shape(root);
    return utf8.encode(jsonEncode(root));
  }

  RestoredCarData decode(List<int> bytes) {
    final root = strictBackupJson(bytes);
    _shape(root);
    return _mapper.toDomain(_payload.decode(root, version: _payloadRules));
  }

  void _shape(Map<String, dynamic> root) {
    exactBackupObject(root, {
      'ownerBirthMonth',
      'car',
      'planConditions',
      'plannedExpenses',
    });
    exactBackupObject(root['car'], {
      'name',
      'firstRegistrationMonth',
      'currentMileageKm',
      'mileageCheckedMonth',
      'annualMileageKm',
    });
    exactBackupObject(root['planConditions'], {
      'fundingPlanEnabled',
      'currentMileageKm',
      'annualMileageKm',
      'ownershipTargetAge',
      'currentCarFundYen',
      'reserveTargetAge',
      'largeRepairReserveYen',
    });
    final expenses = root['plannedExpenses'];
    if (expenses is! List) throw const FormatException('Expected expenses');
    for (final expense in expenses) {
      exactBackupObject(expense, {
        'id',
        'name',
        'amountYen',
        'plannedMonth',
        'basis',
        'memo',
        'status',
      });
    }
  }
}
