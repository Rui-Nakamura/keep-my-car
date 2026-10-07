import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';

import '../plan_test_support.dart';

void main() {
  test(
    'initial Golden Sample extends timeline and preserves reserve calculation',
    () {
      final plan = session();
      final result = plan.reserveResult as RepairReserveSuccess;
      expect(
        (
          result.plannedExpensesOnlyMonthlyYen,
          result.repairIncludedMonthlyYen,
          result.additionalMonthlyYen,
        ),
        (11341, 29808, 18467),
      );
      expect(plan.timeline.map((year) => year.mileageKm), [
        45000,
        49000,
        53000,
        57000,
        61000,
        65000,
        69000,
        73000,
        77000,
        81000,
        85000,
        89000,
        93000,
        97000,
        99333,
      ]);
      expect(plan.timeline.first.year, 2026);
      expect(plan.timeline.last.year, 2040);
      expect(plan.timelinePending, isFalse);
      expect(plan.reservePending, isFalse);
    },
  );
  test('atomic apply, affected calculations once and no-op zero', () {
    final cases = [
      (conditions(), 0, 0),
      (conditions(mileage: 50000, annual: 6000), 1, 0),
      (conditions(fund: 1000000, reserve: 3000000, age: 66), 0, 1),
      (
        conditions(
          mileage: 50000,
          annual: 6000,
          fund: 1000000,
          reserve: 3000000,
          age: 66,
          ownership: 80,
        ),
        1,
        1,
      ),
      (conditions(ownership: 80), 1, 0),
    ];
    for (final entry in cases) {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      expect((calls.timeline, calls.reserve), (1, 1));
      calls.reset();
      expect(plan.apply(entry.$1), isEmpty);
      expect(plan.conditions, entry.$1);
      expect((calls.timeline, calls.reserve), (entry.$2, entry.$3));
    }
  });
  test(
    'invalid set preserves conditions, both results, pending, delta and notice',
    () {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      plan.apply(conditions(annual: 6000, reserve: 3000000));
      final old = plan.conditions;
      final timeline = plan.timeline;
      final reserve = plan.reserveResult;
      final delta = plan.reserveDeltaYen;
      final notice = plan.homeUpdate;
      calls.reset();
      expect(plan.apply(conditions(mileage: 90000, fund: -1)), isNotEmpty);
      expect(plan.conditions, same(old));
      expect(plan.timeline, same(timeline));
      expect(plan.reserveResult, same(reserve));
      expect((plan.timelinePending, plan.reservePending), (true, true));
      expect(plan.reserveDeltaYen, delta);
      expect(plan.homeUpdate, notice);
      expect((calls.timeline, calls.reserve), (0, 0));
    },
  );
  test('pending survives other screen and no change; A-B-C compares B-C', () {
    final plan = session();
    final a = plan.reserveResult as RepairReserveSuccess;
    plan.apply(conditions(reserve: 3000000));
    final b = plan.reserveResult as RepairReserveSuccess;
    expect(
      plan.reserveDeltaYen,
      b.repairIncludedMonthlyYen - a.repairIncludedMonthlyYen,
    );
    final delta = plan.reserveDeltaYen;
    plan.consumeHomeUpdate();
    plan.apply(conditions(annual: 6000, reserve: 3000000));
    expect(plan.reservePending, isTrue);
    expect(plan.reserveDeltaYen, delta);
    expect(plan.homeUpdate, HomeUpdate.timeline);
    plan.apply(plan.conditions);
    expect(plan.reserveDeltaYen, delta);
    expect(plan.timelinePending, isTrue);
    plan.apply(conditions(annual: 6000, reserve: 2500000));
    final c = plan.reserveResult as RepairReserveSuccess;
    expect(
      plan.reserveDeltaYen,
      c.repairIncludedMonthlyYen - b.repairIncludedMonthlyYen,
    );
    expect(plan.homeUpdate, HomeUpdate.reserve);
    plan.consumeHomeUpdate();
    expect(plan.reservePending, isTrue);
    plan.acknowledgeTimeline();
    expect(plan.reservePending, isTrue);
    plan.acknowledgeReserve();
    expect(plan.reservePending, isFalse);
    expect(plan.reserveDeltaYen, isNull);
  });
  test('changed inputs with equal results do not create notifications', () {
    final plan = session(initial: conditions(fund: 1000000000));
    plan.apply(conditions(fund: 999999999));
    expect(plan.reservePending, isFalse);
    expect(plan.homeUpdate, isNull);
    plan.apply(conditions(fund: 999999999));
    expect((plan.timelinePending, plan.reservePending), (false, false));
  });
  test('same result preserves existing pending and delta', () {
    final plan = session();
    plan.apply(conditions(fund: 1000000000));
    final delta = plan.reserveDeltaYen;
    plan.apply(conditions(fund: 999999999));
    expect(plan.reservePending, isTrue);
    expect(plan.reserveDeltaYen, delta);
    expect(plan.homeUpdate, isNull);
  });
  test(
    'success/failure transitions retain result types without fabricated delta',
    () {
      var fail = false;
      final calls = CalculationCalls();
      final plan = session(
        reserveCalculator:
            ({
              required referenceMonth,
              required currentCarFundYen,
              required reserveTargetMonth,
              required largeRepairReserveYen,
              required plannedExpenses,
            }) => fail
            ? const RepairReserveFailure(RepairReserveError.invalidInput)
            : calls.calculateReserve(
                referenceMonth: referenceMonth,
                currentCarFundYen: currentCarFundYen,
                reserveTargetMonth: reserveTargetMonth,
                largeRepairReserveYen: largeRepairReserveYen,
                plannedExpenses: plannedExpenses,
              ),
      );
      plan.apply(conditions(reserve: 3000000));
      fail = true;
      for (final value in [3100000, 3200000]) {
        plan.apply(conditions(reserve: value));
        expect(plan.reserveResult, isA<RepairReserveFailure>());
        expect(plan.reserveDeltaYen, isNull);
        expect(plan.reservePending, isFalse);
      }
      fail = false;
      plan.apply(conditions(reserve: 3300000));
      expect(plan.reserveResult, isA<RepairReserveSuccess>());
      expect(plan.reserveDeltaYen, isNull);
      expect(plan.reservePending, isFalse);
    },
  );
}
