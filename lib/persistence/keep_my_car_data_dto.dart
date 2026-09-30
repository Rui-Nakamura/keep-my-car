/// Versioned storage values only; domain rules belong to the mapper.
class KeepMyCarDataDto {
  KeepMyCarDataDto({
    this.formatVersion = 1,
    required this.ownerBirthMonth,
    required this.car,
    required this.planConditions,
    required List<PlannedExpenseDto> plannedExpenses,
  }) : plannedExpenses = List.unmodifiable(plannedExpenses);

  final int formatVersion;
  final String ownerBirthMonth;
  final CarDto car;
  final PlanConditionsDto planConditions;
  final List<PlannedExpenseDto> plannedExpenses;
}

class CarDto {
  const CarDto({
    required this.name,
    required this.firstRegistrationMonth,
    required this.currentMileageKm,
    required this.mileageCheckedMonth,
    required this.annualMileageKm,
  });

  final String name;
  final String firstRegistrationMonth;
  final int currentMileageKm;
  final String mileageCheckedMonth;
  final int annualMileageKm;
}

class PlanConditionsDto {
  const PlanConditionsDto({
    required this.currentMileageKm,
    required this.annualMileageKm,
    required this.ownershipTargetAge,
    required this.currentCarFundYen,
    required this.reserveTargetAge,
    required this.largeRepairReserveYen,
  });

  final int currentMileageKm;
  final int annualMileageKm;
  final int ownershipTargetAge;
  final int currentCarFundYen;
  final int reserveTargetAge;
  final int largeRepairReserveYen;
}

class PlannedExpenseDto {
  const PlannedExpenseDto({
    required this.id,
    required this.name,
    required this.amountYen,
    required this.plannedMonth,
    required this.basis,
    required this.memo,
    required this.status,
  });

  final int id;
  final String name;
  final int amountYen;
  final String plannedMonth;
  final String basis;
  // The existing domain explicitly permits a null memo.
  final String? memo;
  final String status;
}
