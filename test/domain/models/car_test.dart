import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

void main() {
  test(
    'copyWith changes name without mutating the original or other fields',
    () {
      final original = goldenSample.car;
      final renamed = original.copyWith(name: '私の愛車');
      expect(renamed.name, '私の愛車');
      expect(original.name, 'メルセデスAMG E53');
      expect(renamed.currentMileageKm, original.currentMileageKm);
      expect(renamed.annualMileageKm, original.annualMileageKm);
      expect(renamed.firstRegistrationMonth, original.firstRegistrationMonth);
      expect(renamed.mileageCheckedMonth, original.mileageCheckedMonth);
    },
  );
  test(
    'mileage copy preserves name and both months, including zero mileage',
    () {
      final original = goldenSample.car;
      final updated = original.copyWith(
        currentMileageKm: 0,
        annualMileageKm: 0,
      );
      expect(updated.currentMileageKm, 0);
      expect(updated.annualMileageKm, 0);
      expect(updated.name, original.name);
      expect(updated.firstRegistrationMonth, original.firstRegistrationMonth);
      expect(updated.mileageCheckedMonth, original.mileageCheckedMonth);
      expect(original.currentMileageKm, 45000);
      expect(original.annualMileageKm, 4000);
    },
  );
}
