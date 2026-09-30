import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import '../persistence_app_support.dart';
import '../plan_test_support.dart';

void main() {
  late TestRepository repo;
  late PersistentPlanState state;
  late CalculationCalls calls;
  setUp(() {
    calls = CalculationCalls();
    repo = TestRepository(Loaded(sampleSnapshot()));
    state = PersistentPlanState(
      repository: repo,
      referenceMonth: const YearMonth(2026, 9),
      sessionFactory: (data, reference) => session(
        initial: data.planConditions,
        birth: data.ownerBirthMonth,
        reference: reference,
        registration: data.car.firstRegistrationMonth,
        expenses: data.plannedExpenses,
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      ),
    );
  });
  tearDown(() => state.dispose());

  test(
    'load restores supplied owner, car, plan and expenses and calculates once',
    () async {
      await state.load();
      expect(state.phase, StartupPhase.ready);
      expect(state.ownerBirthMonth, const YearMonth(1970, 4));
      expect(state.session!.plannedExpenses, hasLength(6));
      expect(state.session!.referenceMonth, const YearMonth(2026, 9));
      expect([calls.timeline, calls.reserve], [1, 1]);
      expect(repo.saves, isEmpty);
    },
  );

  for (final success in [false, true]) {
    test(
      'car name save success=$success commits only after completion, never calculates',
      () async {
        await state.load();
        calls.reset();
        final old = state.car;
        final pending = Completer<SaveResult>();
        repo.onSave = (_) => pending.future;
        final request = Future.sync(() => state.saveCarName('新しい愛車'));
        expect(state.car, same(old));
        expect([calls.timeline, calls.reserve], [0, 0]);
        if (success) {
          pending.complete(const Saved());
          await request;
          expect(state.car!.name, '新しい愛車');
        } else {
          final failure = expectLater(
            request,
            throwsA(isA<SaveRequestFailure>()),
          );
          pending.complete(saveFailure());
          await failure;
          expect(state.car, same(old));
        }
        expect([calls.timeline, calls.reserve], [0, 0]);
        expect(repo.saves.single.car.name, '新しい愛車');
      },
    );

    test(
      'plan save success=$success syncs mileage and computes only after commit',
      () async {
        await state.load();
        calls.reset();
        final oldCar = state.car;
        final oldTimeline = state.session!.timeline;
        final oldReserve = state.session!.reserveResult;
        final pending = Completer<SaveResult>();
        repo.onSave = (_) => pending.future;
        final next = conditions(mileage: 50000, annual: 5000, reserve: 3000000);
        final request = Future.sync(() => state.apply(next));
        expect(state.car, same(oldCar));
        expect(state.session!.conditions, conditions());
        expect([calls.timeline, calls.reserve], [0, 0]);
        expect(repo.saves.single.car.currentMileageKm, 50000);
        expect(repo.saves.single.car.annualMileageKm, 5000);
        if (success) {
          pending.complete(const Saved());
          await request;
          expect(state.session!.conditions, next);
          expect(
            state.session!.conditions,
            same(repo.saves.single.planConditions),
          );
          expect(state.car, same(repo.saves.single.car));
          expect(state.car!.currentMileageKm, 50000);
          expect([calls.timeline, calls.reserve], [1, 1]);
        } else {
          final failure = expectLater(
            request,
            throwsA(isA<SaveRequestFailure>()),
          );
          pending.complete(saveFailure());
          await failure;
          expect(state.car, same(oldCar));
          expect(state.session!.timeline, same(oldTimeline));
          expect(state.session!.reserveResult, same(oldReserve));
          expect(state.session!.homeUpdate, isNull);
          expect([calls.timeline, calls.reserve], [0, 0]);
        }
      },
    );

    for (final operation in ['add', 'edit', 'delete']) {
      test(
        '$operation success=$success keeps list, IDs, feedback and calculations until saved',
        () async {
          await state.load();
          calls.reset();
          final old = state.session!.plannedExpenses;
          final pending = Completer<SaveResult>();
          repo.onSave = (_) => pending.future;
          final request = operation == 'delete'
              ? state.deleteExpense(1)
              : state.saveExpense(
                  id: operation == 'edit' ? 1 : null,
                  name: 'テスト予定',
                  month: const YearMonth(2027, 4),
                  amountYen: 100000,
                );
          expect(state.session!.plannedExpenses, same(old));
          expect(state.session!.timelinePending, isFalse);
          expect([calls.timeline, calls.reserve], [0, 0]);
          if (success) {
            pending.complete(const Saved());
            await request;
            // Identity proves every field (including basis/status/memo) and ID
            // is from the saved candidate, not regenerated from editor inputs.
            expect(
              state.session!.plannedExpenses,
              same(repo.saves.single.plannedExpenses),
            );
            expect(
              state.session!.plannedExpenses.length,
              operation == 'add'
                  ? 7
                  : operation == 'delete'
                  ? 5
                  : 6,
            );
            expect([calls.timeline, calls.reserve], [1, 1]);
            if (operation == 'add') {
              expect(state.session!.plannedExpenses.last.id, 7);
            }
          } else {
            final failure = expectLater(
              request,
              throwsA(isA<SaveRequestFailure>()),
            );
            pending.complete(saveFailure());
            await failure;
            expect(state.session!.plannedExpenses, same(old));
            expect([calls.timeline, calls.reserve], [0, 0]);
            expect(state.session!.homeUpdate, isNull);
            if (operation == 'add') {
              repo.onSave = null;
              await state.saveExpense(
                name: '再試行',
                month: const YearMonth(2027, 4),
                amountYen: 0,
              );
              expect(state.session!.plannedExpenses.last.id, 7);
            }
          }
        },
      );
    }
  }

  test('unchanged and invalid edits do not save or calculate', () async {
    await state.load();
    calls.reset();
    await state.saveCarName(state.car!.name);
    await state.apply(state.session!.conditions);
    final expense = state.session!.plannedExpenses.first;
    await state.saveExpense(
      id: expense.id,
      name: expense.name,
      month: expense.plannedMonth,
      amountYen: expense.amountYen,
    );
    expect(await state.saveCarName(''), isNotNull);
    expect(await state.apply(conditions(fund: -1)), isNotEmpty);
    expect(repo.saves, isEmpty);
    expect([calls.timeline, calls.reserve], [0, 0]);
  });

  for (final result in [
    Loaded(sampleSnapshot()),
    Recovered(sampleSnapshot()),
    LoadFailure([saveFailure().issue]),
    const NoData(),
  ]) {
    test(
      'uncertain state reload ${result.runtimeType} uses same repository and disk truth',
      () async {
        await state.load();
        final old = state.car;
        calls.reset();
        repo.saveResult = saveFailure(uncertain: true);
        await expectLater(
          Future.sync(() => state.saveCarName('未確定')),
          throwsA(
            isA<SaveRequestFailure>().having(
              (e) => e.uncertain,
              'uncertain',
              true,
            ),
          ),
        );
        expect(state.phase, StartupPhase.uncertain);
        expect(state.car, same(old));
        expect([calls.timeline, calls.reserve], [0, 0]);
        await expectLater(
          Future.sync(() => state.saveCarName('禁止')),
          throwsA(isA<SaveRequestFailure>()),
        );
        expect(repo.saves, hasLength(1));
        repo.result = result;
        await state.load();
        expect(repo.loads, 2);
        expect(state.phase, switch (result) {
          Loaded() => StartupPhase.ready,
          Recovered() => StartupPhase.recovered,
          NoData() => StartupPhase.noData,
          LoadFailure() => StartupPhase.failure,
        });
        if (result is Loaded || result is Recovered) {
          expect(state.car!.name, sampleSnapshot().car.name);
        }
      },
    );
  }

  test(
    'application guard rejects simultaneous requests without consuming next ID',
    () async {
      await state.load();
      final pending = Completer<SaveResult>();
      repo.onSave = (_) => pending.future;
      final first = state.saveExpense(
        name: '一件目',
        month: const YearMonth(2027, 4),
        amountYen: 0,
      );
      await expectLater(
        state.saveExpense(
          name: '二件目',
          month: const YearMonth(2027, 4),
          amountYen: 0,
        ),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(repo.saves, hasLength(1));
      pending.complete(const Saved());
      await first;
      expect(state.session!.plannedExpenses.last.id, 7);
    },
  );
}
