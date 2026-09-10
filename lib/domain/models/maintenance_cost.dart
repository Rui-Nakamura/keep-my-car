enum MaintenanceFrequency { monthly, yearly, everyTwoYears }

class MaintenanceCost {
  const MaintenanceCost({
    required this.name,
    required this.amountYen,
    required this.frequency,
  });

  final String name;
  final int amountYen;
  final MaintenanceFrequency frequency;
}
