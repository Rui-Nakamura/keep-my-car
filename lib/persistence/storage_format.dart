import 'keep_my_car_data_dto.dart';
import 'persistence_version.dart';

/// Storage grammar validation also applies to manually constructed DTOs.
void validateStorageFormat(KeepMyCarDataDto data) {
  if (data.formatVersion < 1 ||
      data.formatVersion > currentPersistenceVersion) {
    throw FormatException('Unsupported formatVersion: ${data.formatVersion}');
  }
  if (data.formatVersion >= 2 &&
      data.planConditions.fundingPlanEnabled == null) {
    throw const FormatException('Required bool: fundingPlanEnabled');
  }
  if (data.formatVersion < 3 && data.photoId != null) {
    throw const FormatException('photoId requires formatVersion 3');
  }
  if (data.formatVersion >= 3) validatePhotoId(data.photoId);
  validateStorageMonth(data.ownerBirthMonth);
  validateStorageMonth(data.car.firstRegistrationMonth);
  validateStorageMonth(data.car.mileageCheckedMonth);
  for (final expense in data.plannedExpenses) {
    validateStorageMonth(expense.plannedMonth);
    if (!const [
      'quoted',
      'selfEstimate',
      'placeholder',
    ].contains(expense.basis)) {
      throw FormatException('Unknown expense basis: ${expense.basis}');
    }
    if (!const ['planned', 'completed'].contains(expense.status)) {
      throw FormatException('Unknown expense status: ${expense.status}');
    }
  }
}

/// A reference only: validity never depends on a photo file being present.
void validatePhotoId(String? value) {
  if (value != null &&
      (value.length != 36 ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(value))) {
    throw const FormatException('Expected lowercase UUID v4: photoId');
  }
}

void validateStorageMonth(String value) {
  if (value.length != 7 ||
      !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
    throw FormatException('Expected YYYY-MM: $value');
  }
}
