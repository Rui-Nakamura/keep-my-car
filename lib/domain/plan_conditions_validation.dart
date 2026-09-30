import 'models/plan_conditions.dart';
import 'models/year_month.dart';

enum PlanField {
  currentMileage,
  annualMileage,
  ownershipAge,
  fund,
  reserveAge,
  reserve,
}

enum PlanInputError { outOfRange, pastTargetMonth, exceedsOwnershipAge }

int completedYears(YearMonth start, YearMonth reference) =>
    reference.year - start.year - (reference.month < start.month ? 1 : 0);

YearMonth reserveMonth(YearMonth birthMonth, int age) =>
    YearMonth(birthMonth.year + age, birthMonth.month);

/// Fixed rules shared by editing and persistence, independent of today's month.
Map<PlanField, PlanInputError> validatePlanConditionsInvariants(
  PlanConditions conditions,
) {
  final errors = <PlanField, PlanInputError>{};
  void range(PlanField field, int value, int minimum, int maximum) {
    if (value < minimum || value > maximum) {
      errors[field] = PlanInputError.outOfRange;
    }
  }

  range(PlanField.currentMileage, conditions.currentMileageKm, 0, 2000000);
  range(PlanField.annualMileage, conditions.annualMileageKm, 0, 200000);
  range(PlanField.fund, conditions.currentCarFundYen, 0, 1000000000);
  range(PlanField.reserve, conditions.largeRepairReserveYen, 0, 1000000000);
  range(PlanField.ownershipAge, conditions.ownershipTargetAge, 0, 100);
  range(PlanField.reserveAge, conditions.reserveTargetAge, 0, 100);
  if (conditions.reserveTargetAge > conditions.ownershipTargetAge) {
    errors[PlanField.reserveAge] = PlanInputError.exceedsOwnershipAge;
  }
  return errors;
}

/// Editing additionally requires targets that are still current.
Map<PlanField, PlanInputError> validatePlanConditions(
  PlanConditions conditions, {
  required YearMonth birthMonth,
  required YearMonth referenceMonth,
}) {
  final errors = validatePlanConditionsInvariants(conditions);
  if (conditions.ownershipTargetAge <
      completedYears(birthMonth, referenceMonth)) {
    errors[PlanField.ownershipAge] = PlanInputError.outOfRange;
  }
  if (reserveMonth(
        birthMonth,
        conditions.reserveTargetAge,
      ).compareTo(referenceMonth) <
      0) {
    errors[PlanField.reserveAge] = PlanInputError.pastTargetMonth;
  }
  return errors;
}
