import 'year_month.dart';

class Car {
  const Car({
    required this.name,
    required this.firstRegistrationMonth,
    required this.currentMileageKm,
    required this.mileageCheckedMonth,
    required this.annualMileageKm,
  });

  /// User-facing car display name, normalized and validated before saving.
  final String name;
  final YearMonth firstRegistrationMonth;
  final int currentMileageKm;
  final YearMonth mileageCheckedMonth;
  final int annualMileageKm;

  Car copyWith({String? name, int? currentMileageKm, int? annualMileageKm}) =>
      Car(
        name: name ?? this.name,
        firstRegistrationMonth: firstRegistrationMonth,
        currentMileageKm: currentMileageKm ?? this.currentMileageKm,
        mileageCheckedMonth: mileageCheckedMonth,
        annualMileageKm: annualMileageKm ?? this.annualMileageKm,
      );
}
