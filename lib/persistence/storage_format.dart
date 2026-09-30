import 'keep_my_car_data_dto.dart';

/// Storage grammar validation also applies to manually constructed DTOs.
void validateStorageFormat(KeepMyCarDataDto data) {
  if (data.formatVersion != 1) {
    throw FormatException('Unsupported formatVersion: ${data.formatVersion}');
  }
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

void validateStorageMonth(String value) {
  if (value.length != 7 ||
      !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
    throw FormatException('Expected YYYY-MM: $value');
  }
}
