import '../domain/models/car.dart';
import '../domain/models/owner.dart';
import '../domain/models/ownership_goal.dart';
import '../domain/models/major_repair_reserve.dart';
import '../domain/models/planned_expense.dart';
import '../domain/models/maintenance_cost.dart';
import '../domain/models/year_month.dart';

/// Input fixture only, not a domain model or a planning result.
class GoldenSampleScenario {
  const GoldenSampleScenario({
    required this.referenceMonth,
    required this.car,
    required this.owner,
    required this.goal,
    required this.currentCarFundYen,
    required this.reserve,
    required this.plannedExpenses,
    required this.maintenanceCosts,
  });

  final YearMonth referenceMonth;
  final Car car;
  final Owner owner;
  final OwnershipGoal goal;
  final int currentCarFundYen;
  final MajorRepairReserve reserve;
  final List<PlannedExpense> plannedExpenses;
  final List<MaintenanceCost> maintenanceCosts;
}

/// Approved E53 sample plan. Expenses are illustrative, not failure predictions.
/// Const lists keep the fixture immutable; no financial calculations occur here.
const goldenSample = GoldenSampleScenario(
  referenceMonth: YearMonth(2026, 9),
  car: Car(
    name: 'Mercedes-AMG E53',
    firstRegistrationMonth: YearMonth(2018, 8),
    currentMileageKm: 45000,
    mileageCheckedMonth: YearMonth(2026, 9),
    annualMileageKm: 4000,
  ),
  owner: Owner(birthMonth: YearMonth(1970, 4)),
  goal: OwnershipGoal(targetAge: 70),
  currentCarFundYen: 500000,
  reserve: MajorRepairReserve(amountYen: 2000000, targetAge: 65),
  plannedExpenses: [
    PlannedExpense(
      id: 1,
      name: '12Vバッテリー',
      plannedMonth: YearMonth(2027, 4),
      amountYen: 80000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
    PlannedExpense(
      id: 2,
      name: 'タイヤ',
      plannedMonth: YearMonth(2028, 8),
      amountYen: 220000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
    PlannedExpense(
      id: 3,
      name: 'ブレーキ一式',
      plannedMonth: YearMonth(2031, 6),
      amountYen: 800000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
    PlannedExpense(
      id: 4,
      name: '48Vバッテリー',
      plannedMonth: YearMonth(2034, 9),
      amountYen: 500000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
    PlannedExpense(
      id: 5,
      name: '足回り',
      plannedMonth: YearMonth(2037, 8),
      amountYen: 700000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
    PlannedExpense(
      id: 6,
      name: 'タイヤ',
      plannedMonth: YearMonth(2039, 4),
      amountYen: 250000,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
  ],
  maintenanceCosts: [
    MaintenanceCost(
      name: '自動車税等',
      amountYen: 51000,
      frequency: MaintenanceFrequency.yearly,
    ),
    MaintenanceCost(
      name: '任意保険',
      amountYen: 120000,
      frequency: MaintenanceFrequency.yearly,
    ),
    MaintenanceCost(
      name: '駐車場',
      amountYen: 18000,
      frequency: MaintenanceFrequency.monthly,
    ),
    MaintenanceCost(
      name: '燃料',
      amountYen: 12000,
      frequency: MaintenanceFrequency.monthly,
    ),
    MaintenanceCost(
      name: '高速道路',
      amountYen: 5000,
      frequency: MaintenanceFrequency.monthly,
    ),
    MaintenanceCost(
      name: '洗車',
      amountYen: 4000,
      frequency: MaintenanceFrequency.monthly,
    ),
    MaintenanceCost(
      name: '車検法定費用',
      amountYen: 70000,
      frequency: MaintenanceFrequency.everyTwoYears,
    ),
    MaintenanceCost(
      name: '車検点検・整備基本費用',
      amountYen: 100000,
      frequency: MaintenanceFrequency.everyTwoYears,
    ),
    MaintenanceCost(
      name: '法定12ヶ月点検',
      amountYen: 40000,
      frequency: MaintenanceFrequency.yearly,
    ),
  ],
);
