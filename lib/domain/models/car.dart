import 'year_month.dart';

class Car {
  const Car({
    required this.name,
    required this.firstRegistrationMonth,
    required this.currentMileageKm,
    required this.mileageCheckedMonth,
    required this.annualMileageKm,
  });

  final String name;
  final YearMonth firstRegistrationMonth;
  final int currentMileageKm;
  final YearMonth mileageCheckedMonth;
  final int annualMileageKm;
}
