import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/app/save_restriction.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/domain/models/ownership_goal.dart';
import 'package:keep_my_car/domain/models/major_repair_reserve.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/plan_conditions_validation.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/repair_reserve/presentation/repair_reserve_screen.dart';
import 'package:keep_my_car/features/settings/presentation/funding_plan_screen.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_json_codec.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'persistence_app_support.dart';
import 'persistence_app_test.dart' show tapVisible;
import 'plan_test_support.dart';
import 'step15_e1_test.dart' show MemoryStorage, bytes, v2, toggle;

Future<void> tap(WidgetTester t, String text) => tapVisible(t, find.text(text));
Future<void> keyed(WidgetTester t, String key) =>
    tapVisible(t, find.byKey(ValueKey(key)));
Future<void> enter(WidgetTester t, String key, String value) async {
  final field = find.byKey(ValueKey('input-$key'));
  await t.ensureVisible(field);
  await t.enterText(field, value);
  await t.pump();
}

Future<void> openFunding(WidgetTester t) async {
  await tap(t, '設定');
  await keyed(t, 'open-funding-plan');
}

Future<void> chooseAge(WidgetTester t, int age) async {
  await keyed(t, 'input-reserveAge');
  await keyed(t, 'age-option-$age');
}

Future<void> stop(WidgetTester t) async {
  await tap(t, '資金計画を使わない');
  await tapVisible(t, find.widgetWithText(TextButton, '資金計画を使わない').last);
}

class CountingRepository extends KeepMyCarRepository {
  CountingRepository(super.storage);
  int saveCalls = 0;
  @override
  Future<SaveResult> save(RestoredCarData snapshot) {
    saveCalls++;
    return super.save(snapshot);
  }
}

void main() {
  testWidgets(
    'future current detected during save protects UI and bytes without retry',
    (t) async {
      final storage = MemoryStorage()..files[DataFile.current] = bytes(v2());
      final repo = CountingRepository(storage);
      await t.pumpWidget(
        KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
      );
      await t.pumpAndSettle();
      final p = t.widget<HomeScreen>(find.byType(HomeScreen)).session;
      final original = p.conditions;
      await openFunding(t);
      await enter(t, 'reserve', '3000000');
      storage.files[DataFile.current] = bytes({
        'formatVersion': 3,
        'unknown': 'preserve',
      });
      final before = Map<DataFile, List<int>>.from(storage.files);
      await keyed(t, 'save-funding');
      expect(find.text('アプリの更新が必要です'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(FundingPlanScreen), findsNothing);
      for (final label in ['新しく設定する', 'バックアップから復元する', 'データを書き出す', '削除']) {
        expect(find.text(label), findsNothing);
      }
      await t.pump(const Duration(seconds: 3));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(storage.mutations, isEmpty);
      expect(repo.saveCalls, 1);
      expect(storage.files, before);
      expect(p.conditions, original);
      expect(find.text('アプリの更新が必要です'), findsOneWidget);
    },
  );

  testWidgets(
    'stop discards unsaved funding edits and preserves formal values',
    (t) async {
      final p = session();
      final original = p.conditions;
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      await enter(t, 'fund', '123');
      await enter(t, 'reserve', '456');
      await chooseAge(t, 66);
      await stop(t);
      expect(p.conditions, toggle(original, false));
    },
  );

  testWidgets(
    'calculation failure shows settings and result guidance without amounts',
    (t) async {
      final p = session(
        reserveCalculator: ({
          required referenceMonth,
          required currentCarFundYen,
          required reserveTargetMonth,
          required largeRepairReserveYen,
          required plannedExpenses,
        }) => const RepairReserveFailure(RepairReserveError.inconsistentResult),
      );
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      expect(find.text('現在の条件では計算できません'), findsOneWidget);
      await tap(t, '計算結果を確認する');
      expect(find.text('現在の条件では計算できません'), findsOneWidget);
      expect(find.text('必要な積立額'), findsNothing);
      expect(find.byKey(const ValueKey('reserve-delta')), findsNothing);
    },
  );

  testWidgets(
    'restricted existing expense permits viewing but not save or deletion',
    (t) async {
      final repo = TestRepository(
        Loaded(sampleSnapshot(), unsupportedBackupVersion: 3),
      );
      await t.pumpWidget(
        KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
      );
      await t.pumpAndSettle();
      await tap(t, 'すべて見る');
      await tapVisible(t, find.text('確認').first);
      expect(find.text(saveRestrictionMessage), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('save-expense')))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'この予定を削除'),
            )
            .onPressed,
        isNull,
      );
      expect(repo.saves, isEmpty);
      expect(repo.discards, 0);
    },
  );

  for (final unused in [false, true]) {
    testWidgets(
      'age semantics has one labeled button and current value unused=$unused',
      (t) async {
        final handle = t.ensureSemantics();
        try {
          final p = session(
            initial: unused ? toggle(conditions(age: 0), false) : conditions(),
          );
          await t.pumpWidget(testApp(session: p));
          await t.pumpAndSettle();
          await openFunding(t);
          if (unused) await tap(t, '資金計画を設定する');
          final button = find.byKey(const ValueKey('input-reserveAge'));
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          final node = t.getSemantics(button);
          expect(node.label, '大きな修理に備える年齢');
          expect(node.value, unused ? '選択してください' : '65歳');
          var childCount = 0;
          node.visitChildren((child) {
            childCount++;
            return true;
          });
          expect(childCount, 0);
          await t.tap(button);
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('age-option-65')), findsOneWidget);
        } finally {
          handle.dispose();
        }
      },
    );
  }

  for (final field in ['fund', 'reserve']) {
    testWidgets('amount range error mentions only amount: $field', (t) async {
      await t.pumpWidget(testApp());
      await t.pumpAndSettle();
      await openFunding(t);
      await enter(t, field, '1000000001');
      await keyed(t, 'save-funding');
      final error = t.widget<Text>(find.byKey(ValueKey('error-$field'))).data!;
      expect(error, '金額は0〜1,000,000,000円の整数で入力してください。');
      expect(error, isNot(contains('年齢')));
    });
  }

  testWidgets(
    'stopping zero-age funding retains all three values and uses common unselected display',
    (t) async {
      final p = session(initial: conditions(fund: 123, age: 0, reserve: 456));
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      await stop(t);
      expect(
        p.conditions,
        toggle(conditions(fund: 123, age: 0, reserve: 456), false),
      );
      await tap(t, '資金計画を設定する');
      expect(find.text('選択してください'), findsOneWidget);
      expect(find.text('0歳'), findsNothing);
      await keyed(t, 'save-funding');
      expect(p.conditions.fundingPlanEnabled, false);
      expect(p.conditions.currentCarFundYen, 123);
      expect(p.conditions.reserveTargetAge, 0);
      expect(p.conditions.largeRepairReserveYen, 456);
      expect(find.byKey(const ValueKey('error-reserveAge')), findsOneWidget);
    },
  );

  for (final retained in [
    conditions(fund: 0, age: 0, reserve: 0),
    conditions(fund: 123, age: 0, reserve: 456),
    conditions(fund: 123, age: 65, reserve: 456),
  ]) {
    testWidgets(
      'unused display preserves ${retained.currentCarFundYen}/${retained.reserveTargetAge}/${retained.largeRepairReserveYen} without history inference',
      (t) async {
        final original = toggle(retained, false);
        final p = session(initial: original);
        final repo = TestRepository(Loaded(sampleSnapshot(p)));
        await t.pumpWidget(
          KeepMyCarApp(
            repository: repo,
            now: () => DateTime(2026, 9),
            sessionFactory: (_, _) => p,
          ),
        );
        await t.pumpAndSettle();
        await openFunding(t);
        expect(find.text('資金計画を設定する'), findsOneWidget);
        expect(find.text('0歳'), findsNothing);
        await tap(t, '資金計画を設定する');
        expect(
          find.text(original.reserveTargetAge == 0 ? '選択してください' : '65歳'),
          findsOneWidget,
        );
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('input-fund')))
              .controller!
              .text,
          '${original.currentCarFundYen}',
        );
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('input-reserve')))
              .controller!
              .text,
          '${original.largeRepairReserveYen}',
        );
        expect(p.conditions, original);
        expect(repo.saves, isEmpty);
        if (original.reserveTargetAge == 0) {
          await keyed(t, 'save-funding');
          expect(
            find.byKey(const ValueKey('error-reserveAge')),
            findsOneWidget,
          );
          expect(p.conditions, original);
          expect(repo.saves, isEmpty);
        }
        await tap(t, 'キャンセル');
        expect(p.conditions, original);
        expect(repo.saves, isEmpty);
      },
    );
  }

  testWidgets(
    'no valid age candidate does not invent a target or enable funding',
    (t) async {
      final p = session(
        initial: newBasicPlanConditions(
          currentMileageKm: 1,
          annualMileageKm: 0,
          ownershipTargetAge: 56,
        ),
      );
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      await tap(t, '資金計画を設定する');
      await keyed(t, 'input-reserveAge');
      expect(find.text('選択できる年齢がありません。保有目標年齢を確認してください。'), findsOneWidget);
      expect(find.byKey(const ValueKey('age-option-0')), findsNothing);
      expect(p.conditions.fundingPlanEnabled, false);
    },
  );

  testWidgets(
    'same year funding month is distinct from D1 evaluation and ownership month',
    (t) async {
      final p = session(
        initial: conditions(age: 56, ownership: 56),
        birth: const YearMonth(1970, 11),
        reference: const YearMonth(2026, 4),
      );
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await tap(t, '未来タイムラインを見る');
      expect(
        find.byKey(const ValueKey('timeline-funding-2026')),
        findsOneWidget,
      );
      expect(find.text('2026年11月'), findsNWidgets(2));
      expect(find.text('11月時点の見込み'), findsOneWidget);
      expect(find.text('現在'), findsNothing);
      expect(p.timeline, hasLength(1));
    },
  );

  testWidgets(
    'stopped funding survives new app and Backup v2 roundtrip, then resumes retained values',
    (t) async {
      final storage = MemoryStorage()..files[DataFile.current] = bytes(v2());
      KeepMyCarApp app() => KeepMyCarApp(
        repository: KeepMyCarRepository(storage),
        now: () => DateTime(2026, 9),
      );
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      await openFunding(t);
      await stop(t);
      final stopped = t
          .widget<FundingPlanScreen>(find.byType(FundingPlanScreen))
          .session
          .conditions;
      expect(stopped.fundingPlanEnabled, false);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      final home = t.widget<HomeScreen>(find.byType(HomeScreen));
      expect(home.session.conditions, stopped);
      final exported = const BackupV1Codec().encode(
        sampleSnapshot(home.session),
        createdAt: DateTime.utc(2026),
      );
      expect(
        (const BackupV1Codec().decode(
          exported,
        ) as BackupImportSuccess).data.planConditions,
        stopped,
      );
      await openFunding(t);
      expect(find.text('大きな修理に備える年齢：65歳'), findsOneWidget);
      await tapVisible(t, find.widgetWithText(FilledButton, '資金計画を設定する'));
      await keyed(t, 'save-funding');
      final p = t
          .widget<FundingPlanScreen>(find.byType(FundingPlanScreen))
          .session;
      expect(p.conditions.fundingPlanEnabled, true);
      expect(p.conditions.reserveTargetAge, stopped.reserveTargetAge);
      expect(p.conditions.largeRepairReserveYen, stopped.largeRepairReserveYen);
      expect(p.reserveDeltaYen, null);
    },
  );

  testWidgets(
    'first start is explicit, cancellable, validates age and stays after save',
    (t) async {
      final p = session(
        initial: newBasicPlanConditions(
          currentMileageKm: 45000,
          annualMileageKm: 4000,
          ownershipTargetAge: 70,
        ),
      );
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      expect(find.text('資金計画は利用していません'), findsOneWidget);
      expect(find.text('0歳'), findsNothing);
      await tap(t, '資金計画を設定する');
      expect(find.text('選択してください'), findsOneWidget);
      expect(p.conditions.fundingPlanEnabled, false);
      await tap(t, 'キャンセル');
      expect(p.fundingPlanStatus, FundingPlanStatus.unused);
      await tap(t, '資金計画を設定する');
      await keyed(t, 'save-funding');
      expect(find.byKey(const ValueKey('error-reserveAge')), findsOneWidget);
      await chooseAge(t, 65);
      await enter(t, 'reserve', '2000000');
      await keyed(t, 'save-funding');
      expect(find.byType(FundingPlanScreen), findsOneWidget);
      expect(p.conditions.fundingPlanEnabled, true);
      expect(p.conditions.reserveTargetAge, 65);
      expect(p.reservePending, false);
      await tap(t, '計算結果を確認する');
      expect(find.byType(RepairReserveScreen), findsOneWidget);
      expect(find.text('必要な積立額'), findsOneWidget);
    },
  );

  testWidgets(
    'settings preserves pending; result consumes once; stop retains and restart has no stale delta',
    (t) async {
      final p = session();
      p.applyFunding(conditions(reserve: 3000000));
      final delta = p.reserveDeltaYen;
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-update')), findsNothing);
      await openFunding(t);
      expect(p.reservePending, true);
      expect(p.reserveDeltaYen, delta);
      await tap(t, '計算結果を確認する');
      expect(p.reservePending, false);
      expect(p.reserveDeltaYen, null);
      expect(find.byKey(const ValueKey('reserve-delta')), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await stop(t);
      expect(p.fundingPlanStatus, FundingPlanStatus.unused);
      expect(p.conditions.currentCarFundYen, 500000);
      expect(p.conditions.reserveTargetAge, 65);
      expect(p.conditions.largeRepairReserveYen, 3000000);
      expect(find.text('計算結果を確認する'), findsNothing);
      await tapVisible(t, find.widgetWithText(FilledButton, '資金計画を設定する'));
      expect(find.text('65歳'), findsOneWidget);
      await keyed(t, 'save-funding');
      expect(p.fundingPlanStatus, FundingPlanStatus.calculable);
      expect(p.reservePending, false);
      expect(p.reserveDeltaYen, null);
      await tap(t, '計算結果を確認する');
      expect(find.byKey(const ValueKey('reserve-delta')), findsNothing);
    },
  );

  testWidgets(
    'past target stops without validation; restart validates retained age near input',
    (t) async {
      final p = session(initial: conditions(age: 56));
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      expect(find.text('資金計画の設定を確認してください'), findsOneWidget);
      await tap(t, '計算結果を確認する');
      expect(find.text('資金計画の設定を確認してください'), findsOneWidget);
      expect(find.text('必要な積立額'), findsNothing);
      await tap(t, '資金計画の設定を確認する');
      await stop(t);
      expect(p.conditions.reserveTargetAge, 56);
      await tapVisible(t, find.widgetWithText(FilledButton, '資金計画を設定する'));
      await keyed(t, 'save-funding');
      expect(p.conditions.fundingPlanEnabled, false);
      expect(find.byKey(const ValueKey('error-reserveAge')), findsOneWidget);
      expect(find.text('56歳'), findsOneWidget);
    },
  );

  for (final discard in [false, true]) {
    testWidgets(
      'dirty basic navigation discard=$discard uses formal conditions',
      (t) async {
        final p = session();
        await t.pumpWidget(testApp(session: p));
        await t.pumpAndSettle();
        await tap(t, '設定');
        await enter(t, 'annualMileage', '9000');
        await keyed(t, 'open-funding-plan');
        expect(find.text('変更を破棄して移動しますか？'), findsOneWidget);
        await tap(t, discard ? '変更を破棄して移動' : 'キャンセル');
        expect(p.conditions.annualMileageKm, 4000);
        if (discard) {
          expect(find.byType(FundingPlanScreen), findsOneWidget);
          await t.tap(find.byType(BackButton));
          await t.pumpAndSettle();
        } else {
          expect(find.byType(FundingPlanScreen), findsNothing);
        }
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('input-annualMileage')),
              )
              .controller!
              .text,
          discard ? '4,000' : '9,000',
        );
      },
    );
  }

  for (final result in <RepairReserveCalculationResult>[
    const RepairReserveUnused(),
    const RepairReserveNeedsReview(),
    const RepairReserveFailure(RepairReserveError.inconsistentResult),
  ]) {
    testWidgets(
      'non-success result ${result.runtimeType} never consumes or displays old amounts',
      (t) async {
        var viewed = 0;
        await t.pumpWidget(
          MaterialApp(
            home: RepairReserveScreen(
              ownershipGoal: const OwnershipGoal(targetAge: 70),
              reserve: const MajorRepairReserve(targetAge: 0, amountYen: 123),
              result: result,
              updatePending: true,
              deltaYen: 456,
              onViewed: () => viewed++,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(viewed, 0);
        expect(find.text('0歳まで'), findsNothing);
        expect(find.text('123円'), findsNothing);
        expect(find.byKey(const ValueKey('reserve-delta')), findsNothing);
        expect(find.byKey(const ValueKey('reserve-update-text')), findsNothing);
        expect(
          find.text(
            result is RepairReserveUnused
                ? '資金計画は利用していません'
                : result is RepairReserveNeedsReview
                ? '資金計画の設定を確認してください'
                : '現在の条件では計算できません',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'valid zero result is visible; funding save alone does not acknowledge',
    (t) async {
      final p = session(initial: conditions(fund: 1000000000));
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openFunding(t);
      await tap(t, '計算結果を確認する');
      expect(find.text('月 0円'), findsNWidgets(2));
      expect(find.text('資金計画は利用していません'), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await enter(t, 'fund', '0');
      await keyed(t, 'save-funding');
      expect(p.reservePending, true);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('資金計画を利用しています'), findsOneWidget);
      expect(p.reservePending, true);
    },
  );

  for (final status in FundingPlanStatus.values) {
    testWidgets(
      'Timeline funding marker only calculable: $status, totals and pending unchanged',
      (t) async {
        final p = status == FundingPlanStatus.calculationFailed
            ? session(
                reserveCalculator:
                    ({
                      required referenceMonth,
                      required currentCarFundYen,
                      required reserveTargetMonth,
                      required largeRepairReserveYen,
                      required plannedExpenses,
                    }) => const RepairReserveFailure(
                      RepairReserveError.inconsistentResult,
                    ),
              )
            : session(
                initial: status == FundingPlanStatus.unused
                    ? toggle(conditions(), false)
                    : status == FundingPlanStatus.needsReview
                    ? conditions(ownership: 60)
                    : conditions(),
              );
        final total = p.ownershipTargetExpensesTotalYen;
        final count = p.plannedExpenses.length;
        final years = p.timeline;
        await t.pumpWidget(testApp(session: p));
        await t.pumpAndSettle();
        await tap(t, '未来タイムラインを見る');
        expect(
          find.text('資金計画の目標'),
          status == FundingPlanStatus.calculable
              ? findsOneWidget
              : findsNothing,
        );
        if (status == FundingPlanStatus.calculable) {
          expect(find.text('65歳までに2,000,000円'), findsOneWidget);
          expect(find.text('2035年4月'), findsOneWidget);
        }
        expect(p.ownershipTargetExpensesTotalYen, total);
        expect(p.plannedExpenses.length, count);
        expect(p.timeline, same(years));
        expect(p.timelinePending, false);
      },
    );
  }

  testWidgets('funding-only update does not create timeline pending', (
    t,
  ) async {
    final p = session();
    final years = p.timeline;
    await t.pumpWidget(testApp(session: p));
    await t.pumpAndSettle();
    await openFunding(t);
    await chooseAge(t, 66);
    await keyed(t, 'save-funding');
    expect(p.timelinePending, false);
    expect(p.timeline, same(years));
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-update')), findsNothing);
    await tap(t, '未来タイムラインを見る');
    expect(find.text('66歳までに2,000,000円'), findsOneWidget);
    expect(find.text('2036年4月'), findsOneWidget);
  });

  for (final action in ['edit', 'stop', 'restart']) {
    for (final uncertain in [false, true]) {
      testWidgets(
        '$action save failure uncertain=$uncertain retains formal input',
        (t) async {
          final data = sampleSnapshot();
          final initial = action == 'restart'
              ? (
                  ownerBirthMonth: data.ownerBirthMonth,
                  car: data.car,
                  planConditions: toggle(data.planConditions, false),
                  plannedExpenses: data.plannedExpenses,
                )
              : data;
          final repo = TestRepository(Loaded(initial))
            ..saveResult = saveFailure(uncertain: uncertain);
          await t.pumpWidget(
            KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
          );
          await t.pumpAndSettle();
          final p = t.widget<HomeScreen>(find.byType(HomeScreen)).session;
          final original = p.conditions;
          await openFunding(t);
          if (action == 'restart') {
            await tapVisible(t, find.widgetWithText(FilledButton, '資金計画を設定する'));
          }
          if (action == 'stop') {
            await stop(t);
          } else {
            await enter(t, 'reserve', '3000000');
            await keyed(t, 'save-funding');
          }
          expect(p.conditions, original);
          expect(find.text('資金計画を保存しました'), findsNothing);
          if (uncertain) {
            expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
            expect(find.byType(FundingPlanScreen), findsNothing);
          } else {
            expect(find.text(SaveRequestFailure.message), findsOneWidget);
            expect(find.byType(FundingPlanScreen), findsOneWidget);
          }
        },
      );
    }
  }

  testWidgets(
    'funding in-flight save blocks repeated save, stop and back until completion',
    (t) async {
      final repo = TestRepository(Loaded(sampleSnapshot()));
      final pending = Completer<SaveResult>();
      repo.onSave = (_) => pending.future;
      await t.pumpWidget(
        KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
      );
      await t.pumpAndSettle();
      await openFunding(t);
      await enter(t, 'reserve', '3000000');
      await keyed(t, 'save-funding');
      expect(repo.saves, hasLength(1));
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('save-funding')))
            .onPressed,
        isNull,
      );
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(FundingPlanScreen), findsOneWidget);
      pending.complete(const Saved());
      await t.pumpAndSettle();
      expect(find.text('資金計画を保存しました'), findsOneWidget);
    },
  );

  for (final file in ['current', 'backup']) {
    testWidgets(
      'version protected $file has update UI and no destructive choices',
      (t) async {
        final repo = TestRepository(VersionProtected(file: file, version: 3));
        await t.pumpWidget(KeepMyCarApp(repository: repo));
        await t.pumpAndSettle();
        expect(find.text('アプリの更新が必要です'), findsOneWidget);
        expect(find.textContaining('データは削除されていません。'), findsOneWidget);
        expect(find.text('新しく設定する'), findsNothing);
        expect(find.text('バックアップから復元する'), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        expect(repo.saves, isEmpty);
        expect(repo.discards, 0);
      },
    );
  }

  for (final response in ['success', 'cancelled', 'error']) {
    testWidgets(
      'normal current + future backup Export $response preserves all bytes and restriction',
      (t) async {
        final storage = MemoryStorage()
          ..files[DataFile.current] = bytes(v2())
          ..files[DataFile.backup] = bytes({
            'formatVersion': 3,
            'unknown': 'preserve',
          })
          ..files[DataFile.temp] = [1, 2, 3];
        final original = Map<DataFile, List<int>>.from(storage.files);
        const channel = MethodChannel('keep_my_car/backup_file');
        var calls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls++;
              final exported = (call.arguments as Map)['bytes'] as List<int>;
              final imported =
                  const BackupV1Codec().decode(exported) as BackupImportSuccess;
              expect(
                imported.data.planConditions,
                sampleSnapshot().planConditions,
              );
              return {
                'status': response,
                if (response == 'error') 'code': 'ioFailure',
              };
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        await t.pumpWidget(
          KeepMyCarApp(
            repository: KeepMyCarRepository(storage),
            now: () => DateTime(2026, 9),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text(saveRestrictionMessage), findsOneWidget);
        expect(
          t
              .widget<TextButton>(find.widgetWithText(TextButton, '愛車名を編集'))
              .onPressed,
          isNull,
        );
        await tap(t, '設定');
        expect(
          t
              .widget<FilledButton>(find.byKey(const ValueKey('apply-plan')))
              .onPressed,
          isNull,
        );
        await keyed(t, 'open-funding-plan');
        expect(
          t
              .widget<FilledButton>(find.byKey(const ValueKey('save-funding')))
              .onPressed,
          isNull,
        );
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await tap(t, 'データ管理');
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'バックアップから復元する'),
              )
              .onPressed,
          isNull,
        );
        await tap(t, 'データを書き出す');
        expect(calls, 1);
        expect(storage.files, original);
        expect(storage.mutations, isEmpty);
        expect(find.text(saveRestrictionMessage), findsOneWidget);
        expect(
          find.text('データを書き出しました'),
          response == 'success' ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  for (final screen in ['basic', 'funding', 'car', 'expense']) {
    testWidgets('protection discovered on save refreshes open $screen screen', (
      t,
    ) async {
      final repo = TestRepository(Loaded(sampleSnapshot()));
      repo.saveResult = SaveFailure(
        PersistenceIssue(
          PersistenceStage.versionProtection,
          const UnsupportedStorageVersion(3, file: 'backup'),
          StackTrace.current,
        ),
      );
      await t.pumpWidget(
        KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
      );
      await t.pumpAndSettle();
      String key;
      if (screen == 'basic') {
        await tap(t, '設定');
        await enter(t, 'annualMileage', '6000');
        key = 'apply-plan';
      } else if (screen == 'funding') {
        await openFunding(t);
        await enter(t, 'reserve', '3000000');
        key = 'save-funding';
      } else if (screen == 'car') {
        await tap(t, '愛車名を編集');
        await t.enterText(
          find.byKey(const ValueKey('car-name-input')),
          '新しい車名',
        );
        key = '';
      } else {
        await tap(t, '＋ 予定費を追加');
        await t.enterText(
          find.byKey(const ValueKey('expense-input-name')),
          '追加',
        );
        await t.enterText(
          find.byKey(const ValueKey('expense-input-amount')),
          '100',
        );
        key = 'save-expense';
      }
      final button = key.isEmpty
          ? find.widgetWithText(FilledButton, '保存')
          : find.byKey(ValueKey(key));
      await tapVisible(t, button);
      expect(find.text(saveRestrictionMessage), findsOneWidget);
      expect(t.widget<FilledButton>(button).onPressed, isNull);
      expect(repo.saves, hasLength(1));
      expect(find.text('新しく設定する'), findsNothing);
    });
  }

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      'funding 360px scale $scale keyboard, errors, stop dialog and marker remain usable',
      (t) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetViewInsets);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(testApp());
        await t.pumpAndSettle();
        await openFunding(t);
        await enter(t, 'reserve', '1000000001');
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pump();
        await keyed(t, 'save-funding');
        final error = find.byKey(const ValueKey('error-reserve'));
        await t.ensureVisible(error);
        await t.pumpAndSettle();
        expect(t.getRect(error).right, lessThanOrEqualTo(360));
        t.view.resetViewInsets();
        await t.pump();
        await tap(t, '資金計画を使わない');
        await t.ensureVisible(find.text('資金計画を使わない設定にしますか？'));
        expect(t.takeException(), isNull);
        await tap(t, 'キャンセル');
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await tap(t, '未来タイムラインを見る');
        final marker = find.text('65歳までに2,000,000円');
        await t.ensureVisible(marker);
        await t.pumpAndSettle();
        expect(t.getRect(marker).right, lessThanOrEqualTo(360));
        expect(t.takeException(), isNull);
      },
    );
  }
}
