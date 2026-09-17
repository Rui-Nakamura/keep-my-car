import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/plan_conditions_validation.dart';

import '../plan_test_support.dart';

void main() {
  const birth = YearMonth(1970, 4);
  const reference = YearMonth(2026, 9);
  test('six values have equality and hashCode', () {
    expect(conditions(), conditions());
    expect(conditions().hashCode, conditions().hashCode);
    for (final different in [
      conditions(mileage: 1),
      conditions(annual: 1),
      conditions(ownership: 80),
      conditions(age: 60),
      conditions(fund: 1),
      conditions(reserve: 1),
    ]) {
      expect(different, isNot(conditions()));
    }
    expect({conditions(), conditions()}.length, 1);
  });
  test('inclusive numeric limits and age 100', () {
    for (final plan in [
      conditions(mileage: 0, annual: 0, fund: 0, reserve: 0),
      conditions(
        mileage: 2000000,
        annual: 200000,
        fund: 1000000000,
        reserve: 1000000000,
        ownership: 100,
        age: 100,
      ),
    ]) {
      expect(
        validatePlanConditions(
          plan,
          birthMonth: birth,
          referenceMonth: reference,
        ),
        isEmpty,
      );
    }
  });
  test('negative and above-limit inputs are rejected per field', () {
    final cases = [
      (conditions(mileage: -1), PlanField.currentMileage),
      (conditions(mileage: 2000001), PlanField.currentMileage),
      (conditions(annual: -1), PlanField.annualMileage),
      (conditions(annual: 200001), PlanField.annualMileage),
      (conditions(fund: -1), PlanField.fund),
      (conditions(fund: 1000000001), PlanField.fund),
      (conditions(reserve: -1), PlanField.reserve),
      (conditions(reserve: 1000000001), PlanField.reserve),
      (conditions(ownership: 101), PlanField.ownershipAge),
      (conditions(ownership: 55), PlanField.ownershipAge),
    ];
    for (final entry in cases) {
      expect(
        validatePlanConditions(
          entry.$1,
          birthMonth: birth,
          referenceMonth: reference,
        ),
        contains(entry.$2),
      );
    }
  });
  test('birth month boundary, current age, and no automatic correction', () {
    expect(completedYears(birth, reference), 56);
    expect(reserveMonth(birth, 56), const YearMonth(2026, 4));
    expect(
      validatePlanConditions(
        conditions(age: 56),
        birthMonth: birth,
        referenceMonth: reference,
      )[PlanField.reserveAge],
      PlanInputError.pastTargetMonth,
    );
    expect(
      validatePlanConditions(
        conditions(age: 57),
        birthMonth: birth,
        referenceMonth: reference,
      ),
      isEmpty,
    );
    for (final month in [2, 4]) {
      expect(
        validatePlanConditions(
          conditions(age: 56),
          birthMonth: birth,
          referenceMonth: YearMonth(2026, month),
        ),
        isEmpty,
      );
    }
    final invalid = conditions(ownership: 60, age: 65);
    expect(
      validatePlanConditions(
        invalid,
        birthMonth: birth,
        referenceMonth: reference,
      )[PlanField.reserveAge],
      PlanInputError.exceedsOwnershipAge,
    );
    expect(invalid.reserveTargetAge, 65);
  });
}
