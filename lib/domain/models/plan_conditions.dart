/// Formal basic and optional funding inputs, including explicit usage intent.
class PlanConditions {
  const PlanConditions({
    required this.fundingPlanEnabled,
    required this.currentMileageKm,
    required this.annualMileageKm,
    required this.ownershipTargetAge,
    required this.currentCarFundYen,
    required this.reserveTargetAge,
    required this.largeRepairReserveYen,
  });

  final bool fundingPlanEnabled;
  final int currentMileageKm;
  final int annualMileageKm;
  final int ownershipTargetAge;
  final int currentCarFundYen;
  final int reserveTargetAge;
  final int largeRepairReserveYen;

  @override
  bool operator ==(Object other) =>
      other is PlanConditions &&
      fundingPlanEnabled == other.fundingPlanEnabled &&
      currentMileageKm == other.currentMileageKm &&
      annualMileageKm == other.annualMileageKm &&
      ownershipTargetAge == other.ownershipTargetAge &&
      currentCarFundYen == other.currentCarFundYen &&
      reserveTargetAge == other.reserveTargetAge &&
      largeRepairReserveYen == other.largeRepairReserveYen;

  @override
  int get hashCode => Object.hash(
    fundingPlanEnabled,
    currentMileageKm,
    annualMileageKm,
    ownershipTargetAge,
    currentCarFundYen,
    reserveTargetAge,
    largeRepairReserveYen,
  );
}
