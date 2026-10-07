import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/projected_mileage.dart';

void main() {
  test(
    'monthly projection truncates fractions and preserves full-year values',
    () {
      int at(YearMonth month, {int annual = 4000}) => projectedMileageKm(
        currentMileageKm: 45000,
        annualMileageKm: annual,
        referenceMonth: const YearMonth(2026, 9),
        targetMonth: month,
      );
      expect(at(const YearMonth(2026, 8)), 45000);
      expect(at(const YearMonth(2026, 9)), 45000);
      expect(at(const YearMonth(2026, 10)), 45333);
      expect(at(const YearMonth(2027, 9)), 49000);
      expect(at(const YearMonth(2040, 4)), 99333);
      expect(at(const YearMonth(2040, 4), annual: 0), 45000);
      expect(at(const YearMonth(2027, 9), annual: 1), 45001);
      expect(at(const YearMonth(2026, 10), annual: 1), 45000);
    },
  );
}
