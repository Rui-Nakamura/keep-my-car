import '../domain/car_validation.dart';
import '../domain/models/car.dart';
import '../domain/models/plan_conditions.dart';
import '../domain/models/planned_expense.dart';
import '../domain/models/year_month.dart';
import '../domain/plan_conditions_validation.dart';
import '../domain/planned_expense_validation.dart';
import 'keep_my_car_data_dto.dart';
import 'storage_format.dart';

typedef RestoredCarData = ({
  YearMonth ownerBirthMonth,
  Car car,
  PlanConditions planConditions,
  List<PlannedExpense> plannedExpenses,
});

/// Pure conversion boundary. No calendar context, sample values or app state
/// are consulted.
/// Saving and restoring both enforce only time-independent invariants.
/// Invalid domain values throw ArgumentError; storage grammar throws
/// FormatException. Either failure returns no partial aggregate.
class KeepMyCarDataMapper {
  const KeepMyCarDataMapper();

  KeepMyCarDataDto toDto({
    required YearMonth ownerBirthMonth,
    required Car car,
    required PlanConditions planConditions,
    required List<PlannedExpense> plannedExpenses,
  }) {
    _validate(car, planConditions, plannedExpenses);
    final data = KeepMyCarDataDto(
      ownerBirthMonth: ownerBirthMonth.toString(),
      car: CarDto(
        name: validateCarName(car.name).name,
        firstRegistrationMonth: car.firstRegistrationMonth.toString(),
        currentMileageKm: car.currentMileageKm,
        mileageCheckedMonth: car.mileageCheckedMonth.toString(),
        annualMileageKm: car.annualMileageKm,
      ),
      planConditions: PlanConditionsDto(
        currentMileageKm: planConditions.currentMileageKm,
        annualMileageKm: planConditions.annualMileageKm,
        ownershipTargetAge: planConditions.ownershipTargetAge,
        currentCarFundYen: planConditions.currentCarFundYen,
        reserveTargetAge: planConditions.reserveTargetAge,
        largeRepairReserveYen: planConditions.largeRepairReserveYen,
      ),
      plannedExpenses: [
        for (final expense in plannedExpenses)
          PlannedExpenseDto(
            id: expense.id,
            name: expense.name.trim(),
            amountYen: expense.amountYen,
            plannedMonth: expense.plannedMonth.toString(),
            basis: switch (expense.basis) {
              ExpenseBasis.quoted => 'quoted',
              ExpenseBasis.selfEstimate => 'selfEstimate',
              ExpenseBasis.placeholder => 'placeholder',
            },
            memo: expense.memo,
            status: switch (expense.status) {
              PlannedExpenseStatus.planned => 'planned',
              PlannedExpenseStatus.completed => 'completed',
            },
          ),
      ],
    );
    validateStorageFormat(data);
    return data;
  }

  RestoredCarData toDomain(KeepMyCarDataDto data) {
    validateStorageFormat(data);
    final c = data.car;
    final p = data.planConditions;
    final car = Car(
      // Validate the raw name before normalization (CR/LF/Tab must not vanish).
      name: c.name,
      firstRegistrationMonth: _month(c.firstRegistrationMonth),
      currentMileageKm: c.currentMileageKm,
      mileageCheckedMonth: _month(c.mileageCheckedMonth),
      annualMileageKm: c.annualMileageKm,
    );
    final plan = PlanConditions(
      currentMileageKm: p.currentMileageKm,
      annualMileageKm: p.annualMileageKm,
      ownershipTargetAge: p.ownershipTargetAge,
      currentCarFundYen: p.currentCarFundYen,
      reserveTargetAge: p.reserveTargetAge,
      largeRepairReserveYen: p.largeRepairReserveYen,
    );
    final expenses = [
      for (final e in data.plannedExpenses)
        PlannedExpense(
          id: e.id,
          name: e.name.trim(),
          plannedMonth: _month(e.plannedMonth),
          amountYen: e.amountYen,
          basis: switch (e.basis) {
            'quoted' => ExpenseBasis.quoted,
            'selfEstimate' => ExpenseBasis.selfEstimate,
            'placeholder' => ExpenseBasis.placeholder,
            _ => throw FormatException('Unknown expense basis: ${e.basis}'),
          },
          memo: e.memo,
          status: switch (e.status) {
            'planned' => PlannedExpenseStatus.planned,
            'completed' => PlannedExpenseStatus.completed,
            _ => throw FormatException('Unknown expense status: ${e.status}'),
          },
        ),
    ];
    _validate(car, plan, expenses);
    return (
      ownerBirthMonth: _month(data.ownerBirthMonth),
      car: car.copyWith(name: validateCarName(car.name).name),
      planConditions: plan,
      plannedExpenses: List<PlannedExpense>.unmodifiable(expenses),
    );
  }

  YearMonth _month(String value) => YearMonth(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5)),
  );

  void _validate(Car car, PlanConditions plan, List<PlannedExpense> expenses) {
    final name = validateCarName(car.name);
    if (name.error != null) throw ArgumentError.value(name.error, 'car.name');
    final errors = validatePlanConditionsInvariants(plan);
    if (errors.isNotEmpty) throw ArgumentError.value(errors, 'planConditions');
    // Reuse the same mileage bounds without creating storage-only ranges.
    final carErrors = validatePlanConditionsInvariants(
      PlanConditions(
        currentMileageKm: car.currentMileageKm,
        annualMileageKm: car.annualMileageKm,
        ownershipTargetAge: plan.ownershipTargetAge,
        currentCarFundYen: plan.currentCarFundYen,
        reserveTargetAge: plan.reserveTargetAge,
        largeRepairReserveYen: plan.largeRepairReserveYen,
      ),
    );
    if (carErrors.isNotEmpty) throw ArgumentError.value(carErrors, 'car');
    if (car.currentMileageKm != plan.currentMileageKm ||
        car.annualMileageKm != plan.annualMileageKm) {
      throw ArgumentError('Car and PlanConditions mileage must match');
    }
    final ids = <int>{};
    for (final expense in expenses) {
      // Same identity invariant as PlanSession; never renumber or discard.
      if (!ids.add(expense.id)) {
        throw ArgumentError('Duplicate expense ID');
      }
      final errors = validatePlannedExpenseInvariants(
        name: expense.name,
        amount: expense.amountYen.toString(),
      );
      if (errors.isNotEmpty) {
        throw ArgumentError.value(errors, 'plannedExpense');
      }
    }
  }
}
