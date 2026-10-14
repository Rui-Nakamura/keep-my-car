import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expense_editor.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expenses_screen.dart';
import 'package:keep_my_car/features/settings/presentation/plan_settings_screen.dart';
import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'persistence_app_support.dart';
import 'plan_test_support.dart';

PlannedExpense item(int id, {int amount = 0}) => PlannedExpense(
  id: id,
  name: '同じ予定',
  plannedMonth: const YearMonth(2040, 4),
  amountYen: amount,
  basis: ExpenseBasis.placeholder,
  status: PlannedExpenseStatus.planned,
  memo: null,
);
PlanSession reached({List<PlannedExpense>? expenses}) => session(
  reference: const YearMonth(2040, 5),
  expenses: expenses ?? [item(1), item(2)],
);
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> openList(WidgetTester t) => tap(t, find.text('予定費を確認する'));
Future<void> delete(WidgetTester t) async {
  await tap(t, find.text('この予定を削除'));
  await t.tap(find.byKey(const ValueKey('confirm-delete-expense')));
  await t.pumpAndSettle();
}

Future<void> age(WidgetTester t, String field, int value) async {
  await tap(t, find.byKey(ValueKey('input-$field')));
  await tap(t, find.byKey(ValueKey('age-option-$value')));
}

Future<void> validTarget(WidgetTester t) async {
  await age(t, 'ownershipAge', 71);
}

void main() {
  test('December target crosses into January', () {
    for (final e in [
      (const YearMonth(2040, 11), false),
      (const YearMonth(2040, 12), false),
      (const YearMonth(2041, 1), true),
    ]) {
      final p = session(birth: const YearMonth(1970, 12), reference: e.$1);
      expect(p.ownershipTargetReached, e.$2);
    }
  });
  testWidgets(
    'same target month retains add and edit with only current month valid',
    (t) async {
      final p = session(
        reference: const YearMonth(2040, 4),
        expenses: [item(1)],
      );
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await tap(t, find.text('すべて見る'));
      expect(find.text('編集'), findsOneWidget);
      await tap(t, find.text('予定費を追加'));
      await t.enterText(find.byKey(const ValueKey('expense-input-name')), '今月');
      await t.enterText(
        find.byKey(const ValueKey('expense-input-amount')),
        '0',
      );
      await tap(t, find.byKey(const ValueKey('expense-input-month')));
      await tap(t, find.byKey(const ValueKey('expense-year-2040')));
      expect(find.byKey(const ValueKey('expense-month-3')), findsNothing);
      expect(find.byKey(const ValueKey('expense-month-5')), findsNothing);
      await tap(t, find.byKey(const ValueKey('expense-month-4')));
      await tap(t, find.byKey(const ValueKey('save-expense')));
      expect(p.plannedExpenses.length, 2);
      await tap(t, find.byKey(const ValueKey('edit-expense-1')));
      expect(find.byType(TextField), findsNWidgets(2));
      await t.enterText(find.byKey(const ValueKey('expense-input-name')), '変更');
      await tap(t, find.byKey(const ValueKey('save-expense')));
      expect(p.plannedExpenses.first.name, '変更');
    },
  );
  testWidgets(
    'extension reclassifies saved future expense and restores totals',
    (t) async {
      final future = PlannedExpense(
        id: 3,
        name: '将来',
        plannedMonth: const YearMonth(2041, 4),
        amountYen: 500,
        basis: ExpenseBasis.placeholder,
        status: PlannedExpenseStatus.planned,
        memo: null,
      );
      final p = reached(expenses: [item(1), future]);
      await t.pumpWidget(testApp(session: p));
      await t.pumpAndSettle();
      await openList(t);
      expect(find.text('計画外の予定費：2件'), findsOneWidget);
      await tap(t, find.text('保有目標を見直す'));
      await validTarget(t);
      await tap(t, find.byKey(const ValueKey('apply-plan')));
      await tap(t, find.text('すべて見る'));
      expect(find.text('計画外の予定費：1件'), findsOneWidget);
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('included-expenses-total')))
            .data,
        '500円',
      );
      expect(find.text('合計 500円'), findsOneWidget);
      expect(find.text('編集'), findsNWidgets(2));
    },
  );

  for (final e in [
    (const YearMonth(2040, 3), 1, false),
    (const YearMonth(2040, 4), 0, false),
    (const YearMonth(2040, 5), -1, true),
    (const YearMonth(2041, 1), -9, true),
  ]) {
    test('boundary ${e.$1}', () {
      final p = session(reference: e.$1);
      expect(p.monthsUntilOwnershipTarget, e.$2);
      expect(p.ownershipTargetReached, e.$3);
    });
  }
  testWidgets('review is read only; cancel, duplicate ID and final deletion', (
    t,
  ) async {
    final p = reached();
    var saves = 0;
    await t.pumpWidget(
      MaterialApp(
        home: PlannedExpensesScreen(
          session: p,
          onChanged: () {},
          onSaveExpense:
              ({id, required name, required month, required amountYen}) {
                saves++;
                return ExpenseChange.unchanged;
              },
          onDeleteExpense: p.deleteExpense,
        ),
      ),
    );
    expect(find.text('予定費を追加'), findsNothing);
    expect(find.text('編集'), findsNothing);
    expect(find.text('保有目標を見直す'), findsNothing);
    expect(find.text('計画外の予定費：2件'), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('edit-expense-1')));
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('save-expense')), findsNothing);
    expect(find.text('0円'), findsOneWidget);
    await tap(t, find.text('この予定を削除'));
    await tap(t, find.text('キャンセル'));
    expect(p.plannedExpenses.length, 2);
    await delete(t);
    expect(p.plannedExpenses.single.id, 2);
    await tap(t, find.byKey(const ValueKey('edit-expense-2')));
    await delete(t);
    expect(find.text('登録済みの予定費は0件です'), findsOneWidget);
    expect(saves, 0);
  });
  for (final uncertain in [false, true]) {
    testWidgets('deletion failure uncertain=$uncertain preserves data', (
      t,
    ) async {
      final repo = TestRepository(Loaded(sampleSnapshot(reached())))
        ..saveResult = saveFailure(uncertain: uncertain);
      await t.pumpWidget(
        KeepMyCarApp(repository: repo, now: () => DateTime(2040, 5)),
      );
      await t.pumpAndSettle();
      await openList(t);
      await tap(t, find.byKey(const ValueKey('edit-expense-1')));
      await delete(t);
      expect((repo.result as Loaded).data.plannedExpenses.length, 2);
      if (uncertain) {
        expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
        expect(find.byType(PlannedExpenseEditor), findsNothing);
      } else {
        expect(find.byKey(const ValueKey('save-error')), findsOneWidget);
        expect(
          t
              .widget<HomeScreen>(find.byType(HomeScreen, skipOffstage: false))
              .session
              .plannedExpenses
              .length,
          2,
        );
      }
    });
  }
  testWidgets('pending deletion blocks Back and duplicate operations', (
    t,
  ) async {
    final repo = TestRepository(Loaded(sampleSnapshot(reached())));
    final pending = Completer<SaveResult>();
    repo.onSave = (_) => pending.future;
    await t.pumpWidget(
      KeepMyCarApp(repository: repo, now: () => DateTime(2040, 5)),
    );
    await t.pumpAndSettle();
    await openList(t);
    await tap(t, find.byKey(const ValueKey('edit-expense-1')));
    await tap(t, find.text('この予定を削除'));
    await t.tap(find.byKey(const ValueKey('confirm-delete-expense')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(repo.saves.length, 1);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(PlannedExpenseEditor), findsOneWidget);
    expect(
      find
          .byType(AbsorbPointer)
          .evaluate()
          .any((e) => (e.widget as AbsorbPointer).absorbing),
      isTrue,
    );
    pending.complete(const Saved());
    await t.pumpAndSettle();
    expect(repo.saves.length, 1);
    expect(find.byType(PlannedExpenseEditor), findsNothing);
  });
  for (final timeline in [false, true]) {
    for (final action in [
      'cancel',
      'invalid',
      'failure',
      'uncertain',
      'success',
    ]) {
      testWidgets('review timeline=$timeline action=$action', (t) async {
        final calls = CalculationCalls();
        final p = session(
          reference: const YearMonth(2040, 5),
          expenses: [item(1), item(2)],
          timelineCalculator: calls.calculateTimeline,
          reserveCalculator: calls.calculateReserve,
        );
        final repo = TestRepository(Loaded(sampleSnapshot(p)));
        await t.pumpWidget(
          KeepMyCarApp(
            repository: repo,
            now: () => DateTime(2040, 5),
            sessionFactory: (_, _) => p,
          ),
        );
        await t.pumpAndSettle();
        calls.reset();
        await tap(t, find.text(timeline ? '未来タイムラインを見る' : '予定費を確認する'));
        await tap(t, find.text('保有目標を見直す'));
        if (action == 'cancel') {
          await tap(t, find.byType(BackButton));
          expect(repo.saves, isEmpty);
          expect([calls.timeline, calls.reserve], [0, 0]);
        } else {
          if (action != 'invalid') {
            await validTarget(t);
          } else {
            await t.ensureVisible(
              find.byKey(const ValueKey('input-currentMileage')),
            );
            await t.enterText(
              find.byKey(const ValueKey('input-currentMileage')),
              '-1',
            );
          }
          if (action == 'failure' || action == 'uncertain') {
            repo.saveResult = saveFailure(uncertain: action == 'uncertain');
          }
          await tap(t, find.byKey(const ValueKey('apply-plan')));
          if (action == 'invalid' || action == 'failure') {
            expect(find.byType(PlanSettingsScreen), findsOneWidget);
            expect([calls.timeline, calls.reserve], [0, 0]);
            expect(p.conditions.ownershipTargetAge, 70);
            await tap(t, find.byType(BackButton));
          }
          if (action == 'uncertain') {
            expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
            expect(p.conditions.ownershipTargetAge, 70);
            return;
          }
          if (action == 'success') {
            expect(find.byType(PlanSettingsScreen), findsNothing);
            expect(find.byType(FutureTimelineScreen), findsNothing);
            expect(find.byType(PlannedExpensesScreen), findsNothing);
            expect(p.timelinePending, isTrue);
            expect(p.homeUpdate, isNotNull);
            expect([calls.timeline, calls.reserve], [1, 0]);
            await tap(t, find.text('未来タイムラインを見る'));
            final screen = t.widget<FutureTimelineScreen>(
              find.byType(FutureTimelineScreen),
            );
            expect(screen.years, same(p.timeline));
            expect(screen.ownershipTargetReached, isFalse);
            await tap(t, find.byType(BackButton));
            await openList(t);
            expect(find.text('予定費を追加'), findsOneWidget);
            expect(find.text('編集'), findsNWidgets(2));
            await t.pumpWidget(const SizedBox());
            await t.pumpWidget(
              KeepMyCarApp(repository: repo, now: () => DateTime(2040, 5)),
            );
            await t.pumpAndSettle();
            expect(
              t
                  .widget<HomeScreen>(find.byType(HomeScreen))
                  .session
                  .conditions
                  .ownershipTargetAge,
              71,
            );
            return;
          }
        }
        expect(
          find.byType(timeline ? FutureTimelineScreen : PlannedExpensesScreen),
          findsOneWidget,
        );
      });
    }
    testWidgets(
      'caller treats stubbed empty Map as success without formal mutation timeline=$timeline',
      (t) async {
        final p = reached();
        final originalConditions = p.conditions;
        final originalTimeline = p.timeline;
        final originalExpenses = p.plannedExpenses;
        var applies = 0;
        await t.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              car: sampleSnapshot(p).car,
              session: p,
              onApply: (next) {
                applies++;
                // Isolate the caller contract: a normal empty Map is success.
                // An unchanged reached plan cannot pass production validation.
                expect(next, conditions(ownership: 71));
                return {};
              },
              onSaveCarName: (_) => null,
              onSaveExpense: p.saveExpense,
              onDeleteExpense: p.deleteExpense,
              onNavigate: () {},
              onTimelineViewed: () {},
              onReserveViewed: () {},
              onExpensesChanged: () {},
            ),
          ),
        );
        await tap(t, find.text(timeline ? '未来タイムラインを見る' : '予定費を確認する'));
        await tap(t, find.text('保有目標を見直す'));
        await validTarget(t);
        await tap(t, find.byKey(const ValueKey('apply-plan')));
        expect(applies, 1);
        expect(p.conditions, same(originalConditions));
        expect(p.timeline, same(originalTimeline));
        expect(p.plannedExpenses, same(originalExpenses));
        expect(p.homeUpdate, isNull);
        expect(p.timelinePending, isFalse);
        expect(p.reservePending, isFalse);
        expect(find.byType(PlanSettingsScreen), findsNothing);
        expect(
          find.byType(timeline ? FutureTimelineScreen : PlannedExpensesScreen),
          findsNothing,
        );
      },
    );
  }
  testWidgets('360px scale 3 empty list and review controls reachable', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Widget app(PlanSession p) => MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(3)),
        child: child!,
      ),
      home: PlannedExpensesScreen(
        session: p,
        onChanged: () {},
        onSaveExpense: p.saveExpense,
        onDeleteExpense: p.deleteExpense,
        onReviewTarget: () {},
      ),
    );
    await t.pumpWidget(app(reached(expenses: [])));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('保有目標を見直す'));
    expect(t.takeException(), isNull);
    expect(find.text('登録済みの予定費は0件です'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app(reached(expenses: [item(1, amount: 1000000000)])));
    await tap(t, find.byKey(const ValueKey('edit-expense-1')));
    await t.ensureVisible(find.text('この予定を削除'));
    expect(find.text('1,000,000,000円'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
