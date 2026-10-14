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
  PlanConditions conditions, {
  bool legacyV1 = false,
}) {
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
  if (legacyV1 && conditions.reserveTargetAge > conditions.ownershipTargetAge) {
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
  final errors = validatePlanConditionsInvariants(conditions, legacyV1: true);
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

/// Basic editing is independent of auxiliary temporal constraints.
Map<PlanField, PlanInputError> validateBasicPlanConditions(
  PlanConditions conditions, {
  required YearMonth birthMonth,
  required YearMonth referenceMonth,
}) {
  final errors = validatePlanConditionsInvariants(conditions);
  errors.removeWhere(
    (field, _) => !const [
      PlanField.currentMileage,
      PlanField.annualMileage,
      PlanField.ownershipAge,
    ].contains(field),
  );
  if (conditions.ownershipTargetAge <
      completedYears(birthMonth, referenceMonth)) {
    errors[PlanField.ownershipAge] = PlanInputError.outOfRange;
  }
  return errors;
}

/// Temporal and cross-target preconditions, independent of usage and ranges.
/// Past-target errors retain priority when both conditions are violated.
PlanInputError? fundingPlanPreconditionError(
  PlanConditions conditions, {
  required YearMonth birthMonth,
  required YearMonth referenceMonth,
}) {
  if (reserveMonth(
        birthMonth,
        conditions.reserveTargetAge,
      ).compareTo(referenceMonth) <
      0) {
    return PlanInputError.pastTargetMonth;
  }
  if (conditions.reserveTargetAge > conditions.ownershipTargetAge) {
    return PlanInputError.exceedsOwnershipAge;
  }
  return null;
}

Map<PlanField, PlanInputError> validateFundingPlanConditions(
  PlanConditions conditions, {
  required YearMonth birthMonth,
  required YearMonth referenceMonth,
}) {
  final errors = validatePlanConditionsInvariants(conditions);
  errors.removeWhere(
    (field, _) => !const [
      PlanField.fund,
      PlanField.reserveAge,
      PlanField.reserve,
    ].contains(field),
  );
  final preconditionError = fundingPlanPreconditionError(
    conditions,
    birthMonth: birthMonth,
    referenceMonth: referenceMonth,
  );
  if (preconditionError != null) {
    errors[PlanField.reserveAge] = preconditionError;
  }
  return errors;
}

/// New optional plan: the zero target is an internal unused value.
PlanConditions newBasicPlanConditions({
  required int currentMileageKm,
  required int annualMileageKm,
  required int ownershipTargetAge,
}) => PlanConditions(
  fundingPlanEnabled: false,
  currentMileageKm: currentMileageKm,
  annualMileageKm: annualMileageKm,
  ownershipTargetAge: ownershipTargetAge,
  currentCarFundYen: 0,
  reserveTargetAge: 0,
  largeRepairReserveYen: 0,
);

PlanConditions basicPlanCandidate(PlanConditions basic, PlanConditions saved) =>
    PlanConditions(
      fundingPlanEnabled: saved.fundingPlanEnabled,
      currentMileageKm: basic.currentMileageKm,
      annualMileageKm: basic.annualMileageKm,
      ownershipTargetAge: basic.ownershipTargetAge,
      currentCarFundYen: saved.currentCarFundYen,
      reserveTargetAge: saved.reserveTargetAge,
      largeRepairReserveYen: saved.largeRepairReserveYen,
    );

PlanConditions fundingPlanCandidate(
  PlanConditions funding,
  PlanConditions saved,
) => PlanConditions(
  fundingPlanEnabled: funding.fundingPlanEnabled,
  currentMileageKm: saved.currentMileageKm,
  annualMileageKm: saved.annualMileageKm,
  ownershipTargetAge: saved.ownershipTargetAge,
  currentCarFundYen: funding.fundingPlanEnabled
      ? funding.currentCarFundYen
      : saved.currentCarFundYen,
  reserveTargetAge: funding.fundingPlanEnabled
      ? funding.reserveTargetAge
      : saved.reserveTargetAge,
  largeRepairReserveYen: funding.fundingPlanEnabled
      ? funding.largeRepairReserveYen
      : saved.largeRepairReserveYen,
);
