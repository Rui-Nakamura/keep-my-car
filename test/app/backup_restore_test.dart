import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import '../persistence_app_support.dart';
import '../plan_test_support.dart';

const reference = YearMonth(2026, 9);

void expectData(RestoredCarData actual, RestoredCarData expected) {
  expect(actual.ownerBirthMonth, expected.ownerBirthMonth);
  expect(actual.car, same(expected.car));
  expect(actual.planConditions, expected.planConditions);
  expect(actual.plannedExpenses, expected.plannedExpenses);
}

BackupImportSuccess backup({bool empty = false}) {
  final source = sampleSnapshot(
    session(
      birth: const YearMonth(1980, 2),
      initial: conditions(mileage: 12000, annual: 3000, fund: 800000),
      expenses: empty
          ? []
          : [
              const PlannedExpense(
                id: 91,
                name: '復元した予定',
                plannedMonth: YearMonth(2028, 4),
                amountYen: 123456,
                basis: ExpenseBasis.quoted,
                status: PlannedExpenseStatus.planned,
                memo: '見積り',
              ),
            ],
    ),
  );
  final data = (
    ownerBirthMonth: source.ownerBirthMonth,
    car: source.car.copyWith(name: '復元した愛車'),
    planConditions: source.planConditions,
    plannedExpenses: source.plannedExpenses,
  );
  const codec = BackupV1Codec();
  return codec.decode(codec.encode(data, createdAt: DateTime.utc(2026, 9)))
      as BackupImportSuccess;
}

void main() {
  for (final start in ['ready', 'recovered', 'noData', 'failure']) {
    group(start, () {
      late TestRepository repo;
      late PersistentPlanState state;
      late CalculationCalls calls;
      var failPreparation = false;
      setUp(() async {
        repo = TestRepository(switch (start) {
          'ready' => Loaded(sampleSnapshot()),
          'recovered' => Recovered(sampleSnapshot()),
          'noData' => const NoData(),
          _ => LoadFailure([saveFailure().issue]),
        });
        calls = CalculationCalls();
        failPreparation = false;
        state = PersistentPlanState(
          repository: repo,
          referenceMonth: reference,
          sessionFactory: (data, month) {
            if (failPreparation) throw StateError('preparation failed');
            return session(
              initial: data.planConditions,
              birth: data.ownerBirthMonth,
              reference: month,
              registration: data.car.firstRegistrationMonth,
              expenses: data.plannedExpenses,
              timelineCalculator: calls.calculateTimeline,
              reserveCalculator: calls.calculateReserve,
            );
          },
        );
        await state.load();
        calls.reset();
      });
      tearDown(() => state.dispose());

      for (final outcome in ['success', 'failure', 'throw', 'uncertain']) {
        test(
          '$start restore $outcome is atomic across save and notification',
          () async {
            final input = backup();
            final oldOwner = state.ownerBirthMonth;
            final oldCar = state.car;
            final oldSession = state.session;
            final oldPhase = state.phase;
            var notifications = 0;
            void expectOld() {
              expect(state.ownerBirthMonth, same(oldOwner));
              expect(state.car, same(oldCar));
              expect(state.session, same(oldSession));
            }

            state.addListener(() {
              notifications++;
              if (outcome == 'success') {
                expectData(state.snapshot, input.data);
                expect(state.phase, StartupPhase.ready);
                expect(state.session, isNot(same(oldSession)));
              } else {
                expectOld();
                expect(state.phase, StartupPhase.uncertain);
              }
            });
            final pending = Completer<SaveResult>();
            repo.onSave = (candidate) {
              expectOld();
              expect(state.phase, oldPhase);
              expectData(candidate, input.data);
              expect([calls.timeline, calls.reserve], [1, 1]);
              return pending.future;
            };
            final request = state.restoreFromBackup(input);
            expectOld();
            expect(notifications, 0);
            // No session creation can occur after persistence has succeeded.
            failPreparation = true;
            if (outcome == 'success') {
              pending.complete(const Saved());
              await request;
              expectData(state.snapshot, input.data);
              expect(state.session!.referenceMonth, reference);
              expect(state.session!.timeline, isNotEmpty);
              expect(state.session!.reserveResult, isNotNull);
              final expected = session(
                initial: input.data.planConditions,
                birth: input.data.ownerBirthMonth,
                reference: reference,
                registration: input.data.car.firstRegistrationMonth,
                expenses: input.data.plannedExpenses,
              );
              expect(
                state.session!.timeline.map(
                  (y) =>
                      (y.year, y.ownerAge, y.carAge, y.mileageKm, y.totalYen),
                ),
                expected.timeline.map(
                  (y) =>
                      (y.year, y.ownerAge, y.carAge, y.mileageKm, y.totalYen),
                ),
              );
              final actualReserve =
                  state.session!.reserveResult as RepairReserveSuccess;
              final expectedReserve =
                  expected.reserveResult as RepairReserveSuccess;
              expect(
                (
                  actualReserve.plannedExpensesOnlyMonthlyYen,
                  actualReserve.repairIncludedMonthlyYen,
                  actualReserve.additionalMonthlyYen,
                ),
                (
                  expectedReserve.plannedExpensesOnlyMonthlyYen,
                  expectedReserve.repairIncludedMonthlyYen,
                  expectedReserve.additionalMonthlyYen,
                ),
              );
              expect(state.session!.timelinePending, isFalse);
              expect(state.session!.reservePending, isFalse);
              expect(notifications, 1);
              expect([calls.timeline, calls.reserve], [1, 1]);
              expect(
                state.session!
                    .prepareExpense(
                      name: '追加',
                      month: const YearMonth(2027, 1),
                      amountYen: 0,
                    )
                    .expenses
                    .last
                    .id,
                92,
              );
            } else {
              final check = expectLater(
                request,
                throwsA(
                  isA<SaveRequestFailure>().having(
                    (e) => e.uncertain,
                    'uncertain',
                    outcome == 'uncertain',
                  ),
                ),
              );
              if (outcome == 'throw') {
                pending.completeError(
                  StateError('unexpected repository error'),
                );
              } else {
                pending.complete(
                  saveFailure(uncertain: outcome == 'uncertain'),
                );
              }
              await check;
              expectOld();
              expect(
                state.phase,
                outcome == 'uncertain' ? StartupPhase.uncertain : oldPhase,
              );
              expect(notifications, outcome == 'uncertain' ? 1 : 0);
            }
          },
        );
      }

      test(
        '$start preparation exception does not save and permits retry',
        () async {
          final old = (
            state.ownerBirthMonth,
            state.car,
            state.session,
            state.phase,
          );
          var notifications = 0;
          state.addListener(() => notifications++);
          failPreparation = true;
          await expectLater(
            state.restoreFromBackup(backup()),
            throwsA(isA<SaveRequestFailure>()),
          );
          expect((
            state.ownerBirthMonth,
            state.car,
            state.session,
            state.phase,
          ), old);
          expect(repo.saves, isEmpty);
          expect(notifications, 0);
          failPreparation = false;
          await state.restoreFromBackup(backup());
          expect(state.phase, StartupPhase.ready);
        },
      );

      test('$start candidate copy exception preserves state', () async {
        final old = (
          state.ownerBirthMonth,
          state.car,
          state.session,
          state.phase,
        );
        final data = backup().data;
        await expectLater(
          state.restoreFromBackup(
            BackupImportSuccess((
              ownerBirthMonth: data.ownerBirthMonth,
              car: data.car,
              planConditions: data.planConditions,
              plannedExpenses: ThrowingExpenses(),
            )),
          ),
          throwsA(isA<SaveRequestFailure>()),
        );
        expect((
          state.ownerBirthMonth,
          state.car,
          state.session,
          state.phase,
        ), old);
        expect(repo.saves, isEmpty);
        await state.restoreFromBackup(backup());
        expect(state.phase, StartupPhase.ready);
      });

      test(
        '$start rollback issues require existing reload before retry',
        () async {
          repo.saveResult = saveFailure(uncertain: true);
          await expectLater(
            state.restoreFromBackup(backup()),
            throwsA(isA<SaveRequestFailure>()),
          );
          expect(state.phase, StartupPhase.uncertain);
          await expectLater(
            state.restoreFromBackup(backup()),
            throwsA(isA<SaveRequestFailure>()),
          );
          expect(repo.saves, hasLength(1));
          final restored = backup().data;
          repo.result = Loaded(restored);
          await state.load();
          expect(repo.loads, 2);
          expectData(state.snapshot, restored);
          expect(state.phase, StartupPhase.ready);
        },
      );
    });
  }

  test(
    'loading and in-flight load reject restore without preparation',
    () async {
      final pending = Completer<LoadResult>();
      final repo = TestRepository(const NoData())
        ..onLoad = () => pending.future;
      final state = PersistentPlanState(
        repository: repo,
        referenceMonth: reference,
        sessionFactory: (_, _) => throw StateError('must not prepare'),
      );
      addTearDown(state.dispose);
      await expectLater(
        state.restoreFromBackup(backup()),
        throwsA(isA<SaveRequestFailure>()),
      );
      final loading = state.load();
      await expectLater(
        state.restoreFromBackup(backup()),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(repo.saves, isEmpty);
      pending.complete(const NoData());
      await loading;
    },
  );

  for (final restoring in [false, true]) {
    test(
      'in-flight ${restoring ? "restore" : "edit"} blocks other operations',
      () async {
        final repo = TestRepository(Loaded(sampleSnapshot()));
        final state = PersistentPlanState(
          repository: repo,
          referenceMonth: reference,
        );
        addTearDown(state.dispose);
        await state.load();
        final pending = Completer<SaveResult>();
        repo.onSave = (_) => pending.future;
        final Future<void> first = restoring
            ? state.restoreFromBackup(backup())
            : Future.sync(() => state.saveCarName('編集中')).then((_) {});
        await expectLater(
          state.restoreFromBackup(backup()),
          throwsA(isA<SaveRequestFailure>()),
        );
        await expectLater(
          Future.sync(() => state.saveCarName('競合')),
          throwsA(isA<SaveRequestFailure>()),
        );
        await state.load();
        expect(repo.loads, 1);
        expect(repo.saves, hasLength(1));
        pending.complete(const Saved());
        await first;
      },
    );
  }

  test('Failure still rejects ordinary saves and initialize', () async {
    final repo = TestRepository(Loaded(sampleSnapshot()));
    final state = PersistentPlanState(
      repository: repo,
      referenceMonth: reference,
    );
    addTearDown(state.dispose);
    await state.load();
    repo.result = LoadFailure([saveFailure().issue]);
    await state.load();
    final old = state.session;
    await expectLater(
      Future.sync(() => state.saveCarName('禁止')),
      throwsA(isA<SaveRequestFailure>()),
    );
    await expectLater(
      state.initialize(backup(empty: true).data),
      throwsA(isA<SaveRequestFailure>()),
    );
    expect(state.phase, StartupPhase.failure);
    expect(state.session, same(old));
    expect(repo.saves, isEmpty);
    repo.saveResult = saveFailure();
    await expectLater(
      state.restoreFromBackup(backup()),
      throwsA(isA<SaveRequestFailure>()),
    );
    expect(state.session, same(old));
    expect(state.phase, StartupPhase.failure);
  });

  test('empty restored list restarts existing allocation at one', () async {
    final repo = TestRepository(Loaded(sampleSnapshot()));
    final state = PersistentPlanState(
      repository: repo,
      referenceMonth: reference,
    );
    addTearDown(state.dispose);
    await state.load();
    await state.restoreFromBackup(backup(empty: true));
    await state.saveExpense(
      name: '初回',
      month: const YearMonth(2027, 1),
      amountYen: 0,
    );
    expect(state.session!.plannedExpenses.single.id, 1);
  });
}

class ThrowingExpenses extends ListBase<PlannedExpense> {
  @override
  int get length => throw StateError('unexpected candidate read failure');
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  PlannedExpense operator [](int index) => throw StateError('read failure');
  @override
  void operator []=(int index, PlannedExpense value) =>
      throw UnsupportedError('read only');
}
