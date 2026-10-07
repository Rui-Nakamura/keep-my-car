import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';

import '../plan_test_support.dart';

void main() {
  test('month edits change displayed order without moving original positions; same-month order remains stable', () {
    final plan = session(expenses: []);
    for (final name in ['先頭', '末尾']) {
      plan.saveExpense(
        name: name,
        month: const YearMonth(2027, 4),
        amountYen: 1,
      );
    }
    final ids = plan.plannedExpenses.map((e) => e.id).toList();
    plan.saveExpense(
      id: ids.first,
      name: '先頭',
      month: const YearMonth(2028, 4),
      amountYen: 1,
    );
    expect(plan.plannedExpenses.map((e) => e.id), ids);
    expect(
      plan.timeline.expand((y) => y.expenses).map((e) => e.id),
      ids.reversed,
    );
    plan.saveExpense(
      id: ids.first,
      name: '先頭',
      month: const YearMonth(2027, 4),
      amountYen: 1,
    );
    expect(plan.plannedExpenses.map((e) => e.id), ids);
    expect(plan.timeline[1].expenses.map((e) => e.id), ids);
  });

  test('append duplicates with unique IDs, zero and maximum; each calculation once', () {
    final calls = CalculationCalls();
    final plan = session(
      expenses: [],
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    for (final amount in [0, 0, 1000000000]) {
      calls.reset();
      expect(
        plan.saveExpense(
          name: '　車検 と　点検 ',
          month: plan.referenceMonth,
          amountYen: amount,
        ),
        ExpenseChange.added,
      );
      expect((calls.timeline, calls.reserve), (1, 1));
    }
    expect(plan.plannedExpenses.map((e) => e.id).toSet().length, 3);
    expect(plan.plannedExpenses.map((e) => e.amountYen), [0, 0, 1000000000]);
    for (final e in plan.plannedExpenses) {
      expect(e.name, '車検 と　点検');
      expect(e.basis, ExpenseBasis.placeholder);
      expect(e.status, PlannedExpenseStatus.planned);
      expect(e.memo, isNull);
    }
    expect(() => plan.plannedExpenses.clear(), throwsUnsupportedError);
    expect(plan.timeline.first.expenses.length, 3);
  });

  test('edit preserves ID, original position and metadata; trim no-op keeps snapshots', () {
    final calls = CalculationCalls();
    final original = PlannedExpense(
      id: 20,
      name: '車検',
      plannedMonth: const YearMonth(2027, 1),
      amountYen: 100,
      basis: ExpenseBasis.quoted,
      memo: '残す',
      status: PlannedExpenseStatus.completed,
    );
    final plan = session(
      expenses: [original],
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    plan.saveExpense(name: '別の予定', month: plan.referenceMonth, amountYen: 0);
    calls.reset();
    expect(
      plan.saveExpense(
        id: 20,
        name: '車検更新',
        month: const YearMonth(2028, 1),
        amountYen: 200,
      ),
      ExpenseChange.updated,
    );
    expect((calls.timeline, calls.reserve), (1, 1));
    final edited = plan.plannedExpenses.first;
    expect((edited.id, edited.name, edited.amountYen), (20, '車検更新', 200));
    expect(
      (edited.basis, edited.memo, edited.status),
      (original.basis, original.memo, original.status),
    );
    final list = plan.plannedExpenses;
    final timeline = plan.timeline;
    final reserve = plan.reserveResult;
    final pending = (
      plan.timelinePending,
      plan.reservePending,
      plan.reserveDeltaYen,
      plan.homeUpdate,
    );
    calls.reset();
    expect(
      plan.saveExpense(
        id: 20,
        name: '　車検更新 ',
        month: edited.plannedMonth,
        amountYen: 200,
      ),
      ExpenseChange.unchanged,
    );
    expect(plan.plannedExpenses, same(list));
    expect(plan.timeline, same(timeline));
    expect(plan.reserveResult, same(reserve));
    expect((
      plan.timelinePending,
      plan.reservePending,
      plan.reserveDeltaYen,
      plan.homeUpdate,
    ), pending);
    expect((calls.timeline, calls.reserve), (0, 0));
  });

  test('physical deletion targets one duplicate and IDs are not reused', () {
    final calls = CalculationCalls();
    final plan = session(
      expenses: [],
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    for (var i = 0; i < 2; i++) {
      plan.saveExpense(name: '同じ', month: plan.referenceMonth, amountYen: 1);
    }
    final first = plan.plannedExpenses.first;
    final last = plan.plannedExpenses.last;
    calls.reset();
    expect(plan.deleteExpense(last.id), ExpenseChange.deleted);
    expect(plan.plannedExpenses.single, same(first));
    expect((calls.timeline, calls.reserve), (1, 1));
    calls.reset();
    expect(plan.deleteExpense(last.id), ExpenseChange.unchanged);
    expect((calls.timeline, calls.reserve), (0, 0));
    plan.saveExpense(name: '同じ', month: plan.referenceMonth, amountYen: 1);
    expect(plan.plannedExpenses.last.id, greaterThan(last.id));
    plan.deleteExpense(first.id);
    plan.deleteExpense(plan.plannedExpenses.single.id);
    expect(plan.plannedExpenses, isEmpty);
    expect(plan.timeline.every((y) => y.expenses.isEmpty), isTrue);
  });

  test('invalid saves do not mutate or calculate, including out-of-range unchanged edit', () {
    final calls = CalculationCalls();
    final plan = session(
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    plan.apply(conditions(ownership: 60, age: 60));
    final list = plan.plannedExpenses;
    calls.reset();
    final outside = list.last;
    for (final input in [
      ('', plan.referenceMonth, 1),
      ('車' * 41, plan.referenceMonth, 1),
      ('車検', plan.referenceMonth, -1),
      ('車検', plan.referenceMonth, 1000000001),
      ('車検', const YearMonth(2026, 8), 1),
      ('車検', const YearMonth(2030, 5), 1),
    ]) {
      expect(
        () => plan.saveExpense(
          name: input.$1,
          month: input.$2,
          amountYen: input.$3,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => plan.saveExpense(
        id: outside.id,
        name: outside.name,
        month: outside.plannedMonth,
        amountYen: outside.amountYen,
      ),
      throwsArgumentError,
    );
    expect(plan.plannedExpenses, same(list));
    expect((calls.timeline, calls.reserve), (0, 0));
    expect(plan.deleteExpense(outside.id), ExpenseChange.deleted);
    expect((calls.timeline, calls.reserve), (1, 1));
  });

  test('shorten filters both calculator inputs; extend restores target-bounded timeline', () {
    final calls = CalculationCalls();
    List<PlannedExpense> reserveInput = [];
    final plan = session(
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator:
          ({
            required referenceMonth,
            required currentCarFundYen,
            required reserveTargetMonth,
            required largeRepairReserveYen,
            required plannedExpenses,
          }) {
            reserveInput = plannedExpenses;
            return calls.calculateReserve(
              referenceMonth: referenceMonth,
              currentCarFundYen: currentCarFundYen,
              reserveTargetMonth: reserveTargetMonth,
              largeRepairReserveYen: largeRepairReserveYen,
              plannedExpenses: plannedExpenses,
            );
          },
    );
    final list = plan.plannedExpenses;
    calls.reset();
    expect(
      plan.apply(conditions(ownership: 60, age: 60, annual: 5000)),
      isEmpty,
    );
    expect((calls.timeline, calls.reserve), (1, 1));
    expect(plan.plannedExpenses, same(list));
    expect(plan.includedExpenses.map((e) => e.name), ['12Vバッテリー', 'タイヤ']);
    expect(reserveInput, plan.includedExpenses);
    expect(plan.timeline.expand((y) => y.expenses).map((e) => e.name), [
      '12Vバッテリー',
      'タイヤ',
    ]);
    expect(
      plan.timeline.map((y) => y.totalYen).reduce((a, b) => a + b),
      300000,
    );
    expect((plan.timeline.first.year, plan.timeline.last.year), (2026, 2030));
    calls.reset();
    plan.apply(conditions());
    expect((calls.timeline, calls.reserve), (1, 1));
    expect(plan.includedExpenses, list);
    expect(
      plan.timeline.map((y) => y.totalYen).reduce((a, b) => a + b),
      2550000,
    );
    expect(
      (plan.reserveResult as RepairReserveSuccess).repairIncludedMonthlyYen,
      29808,
    );
  });

  test('ownership-only change preserves reserve window and value; filtered input excludes later rows', () {
    final calls = CalculationCalls();
    final plan = session(
      timelineCalculator: calls.calculateTimeline,
      reserveCalculator: calls.calculateReserve,
    );
    final before = plan.reserveResult as RepairReserveSuccess;
    calls.reset();
    plan.apply(conditions(ownership: 65));
    expect((calls.timeline, calls.reserve), (1, 1));
    expect(
      plan.includedExpenses.every(
        (e) => e.plannedMonth.compareTo(const YearMonth(2035, 4)) <= 0,
      ),
      isTrue,
    );
    expect(
      (plan.reserveResult as RepairReserveSuccess).repairIncludedMonthlyYen,
      before.repairIncludedMonthlyYen,
    );
    expect((plan.timelinePending, plan.reservePending), (true, false));
  });

  test('zero/name changes notify timeline only; unaffected pending and B-C reserve delta survive', () {
    final plan = session(expenses: [], initial: conditions(fund: 0));
    plan.saveExpense(name: '無料', month: plan.referenceMonth, amountYen: 0);
    expect((plan.timelinePending, plan.reservePending), (true, false));
    final id = plan.plannedExpenses.single.id;
    plan.acknowledgeTimeline();
    plan.saveExpense(
      id: id,
      name: '無料更新',
      month: plan.referenceMonth,
      amountYen: 0,
    );
    expect((plan.timelinePending, plan.reservePending), (true, false));
    plan.saveExpense(
      id: id,
      name: '有料',
      month: plan.referenceMonth,
      amountYen: 1000000,
    );
    final b = plan.reserveResult as RepairReserveSuccess;
    final delta = plan.reserveDeltaYen;
    plan.saveExpense(
      id: id,
      name: '名称だけ',
      month: plan.referenceMonth,
      amountYen: 1000000,
    );
    expect(plan.reservePending, isTrue);
    expect(plan.reserveDeltaYen, delta);
    plan.saveExpense(
      id: id,
      name: '有料',
      month: plan.referenceMonth,
      amountYen: 2000000,
    );
    final c = plan.reserveResult as RepairReserveSuccess;
    expect(
      plan.reserveDeltaYen,
      c.repairIncludedMonthlyYen - b.repairIncludedMonthlyYen,
    );
    plan.acknowledgeTimeline();
    final pendingDelta = plan.reserveDeltaYen;
    plan.saveExpense(
      name: '10年より後',
      month: plan.ownershipTargetMonth,
      amountYen: 0,
    );
    expect(plan.timelinePending, isTrue);
    expect(plan.reservePending, isTrue);
    expect(plan.reserveDeltaYen, pendingDelta);
  });
}
