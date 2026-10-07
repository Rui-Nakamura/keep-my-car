import 'models/year_month.dart';

/// Prorates annual mileage by elapsed calendar months and truncates below 1 km.
/// Past months retain the current mileage; historical mileage is not inferred.
int projectedMileageKm({
  required int currentMileageKm,
  required int annualMileageKm,
  required YearMonth referenceMonth,
  required YearMonth targetMonth,
}) {
  final months =
      (targetMonth.year - referenceMonth.year) * 12 +
      targetMonth.month -
      referenceMonth.month;
  return currentMileageKm + (months > 0 ? annualMileageKm * months ~/ 12 : 0);
}
