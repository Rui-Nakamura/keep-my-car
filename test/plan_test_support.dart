import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/models/plan_conditions.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/features/timeline/future_timeline_calculator.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

PlanConditions conditions({
  int mileage = 45000,
  int annual = 4000,
  int ownership = 70,
  int fund = 500000,
  int age = 65,
  int reserve = 2000000,
}) => PlanConditions(
  currentMileageKm: mileage,
  annualMileageKm: annual,
  ownershipTargetAge: ownership,
  currentCarFundYen: fund,
  reserveTargetAge: age,
  largeRepairReserveYen: reserve,
);

PlanSession session({
  PlanConditions? initial,
  YearMonth? birth,
  YearMonth? reference,
  YearMonth? registration,
  List<PlannedExpense>? expenses,
  TimelineCalculator timelineCalculator = calculateFutureTimeline,
  ReserveCalculator reserveCalculator = calculateRepairReserve,
}) => PlanSession(
  conditions: initial ?? conditions(),
  birthMonth: birth ?? goldenSample.owner.birthMonth,
  referenceMonth: reference ?? goldenSample.referenceMonth,
  firstRegistrationMonth:
      registration ?? goldenSample.car.firstRegistrationMonth,
  plannedExpenses: expenses ?? goldenSample.plannedExpenses,
  timelineCalculator: timelineCalculator,
  reserveCalculator: reserveCalculator,
);

class CalculationCalls {
  int timeline = 0;
  int reserve = 0;
  List<TimelineYearData> calculateTimeline({
    required YearMonth referenceMonth,
    required YearMonth birthMonth,
    required YearMonth firstRegistrationMonth,
    required YearMonth ownershipTargetMonth,
    required int currentMileageKm,
    required int annualMileageKm,
    required List<PlannedExpense> plannedExpenses,
  }) {
    timeline++;
    return calculateFutureTimeline(
      referenceMonth: referenceMonth,
      birthMonth: birthMonth,
      firstRegistrationMonth: firstRegistrationMonth,
      ownershipTargetMonth: ownershipTargetMonth,
      currentMileageKm: currentMileageKm,
      annualMileageKm: annualMileageKm,
      plannedExpenses: plannedExpenses,
    );
  }

  RepairReserveCalculationResult calculateReserve({
    required YearMonth referenceMonth,
    required int currentCarFundYen,
    required YearMonth reserveTargetMonth,
    required int largeRepairReserveYen,
    required List<PlannedExpense> plannedExpenses,
  }) {
    reserve++;
    return calculateRepairReserve(
      referenceMonth: referenceMonth,
      currentCarFundYen: currentCarFundYen,
      reserveTargetMonth: reserveTargetMonth,
      largeRepairReserveYen: largeRepairReserveYen,
      plannedExpenses: plannedExpenses,
    );
  }

  void reset() {
    timeline = 0;
    reserve = 0;
  }
}
