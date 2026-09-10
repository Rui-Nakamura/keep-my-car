/// Funds to secure by targetAge and retain as a minimum balance until ownership ends.
class MajorRepairReserve {
  const MajorRepairReserve({required this.amountYen, required this.targetAge});

  final int amountYen;
  final int targetAge;
}
