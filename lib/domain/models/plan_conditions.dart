/// The six editable values committed together for one calculation.
class PlanConditions {
  const PlanConditions({
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

  @override
  bool operator ==(Object other) =>
      other is PlanConditions &&
      currentMileageKm == other.currentMileageKm &&
      annualMileageKm == other.annualMileageKm &&
      ownershipTargetAge == other.ownershipTargetAge &&
      currentCarFundYen == other.currentCarFundYen &&
      reserveTargetAge == other.reserveTargetAge &&
      largeRepairReserveYen == other.largeRepairReserveYen;

  @override
  int get hashCode => Object.hash(
    currentMileageKm,
    annualMileageKm,
    ownershipTargetAge,
    currentCarFundYen,
    reserveTargetAge,
    largeRepairReserveYen,
  );
}
