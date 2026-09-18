import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expense_editor.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expenses_screen.dart';
import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';
import 'package:keep_my_car/features/repair_reserve/presentation/repair_reserve_screen.dart';

import 'plan_test_support.dart';

Finder field(String name) => find.byKey(ValueKey('expense-input-$name'));
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // Let TextField's deferred caret scrolling finish before revealing a button.
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterExpense(
  WidgetTester tester,
  String name,
  String amount,
) async {
  await tester.ensureVisible(field('name'));
  await tester.enterText(field('name'), name);
  await tester.ensureVisible(field('amount'));
  await tester.enterText(field('amount'), amount);
  await tester.pump();
}

Future<void> save(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const ValueKey('save-expense')));
Future<void> openList(WidgetTester tester) =>
    tapVisible(tester, find.text('予定費を見る・追加する'));
Future<void> add(WidgetTester tester) =>
    tapVisible(tester, find.widgetWithText(FilledButton, '予定費を追加'));
Future<void> edit(WidgetTester tester, int id) =>
    tapVisible(tester, find.byKey(ValueKey('edit-expense-$id')));
Future<void> back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void safeLayout(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(paragraph.didExceedMaxLines, isFalse);
    final inAppBar = find.ancestor(
      of: find.byWidget(element.widget),
      matching: find.byType(AppBar),
    );
    if (inAppBar.evaluate().isEmpty) {
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
    }
  }
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    expect(state.position.axis, Axis.vertical);
  }
  expect(tester.takeException(), isNull);
}

Future<void> pumpApp(
  WidgetTester tester,
  PlanSession plan, {
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: KeepMyCarApp(session: plan),
    ),
  );
}

void main() {
  testWidgets(
    'outside expense can be deleted without changing its month; empty and add notice at scale 3',
    (tester) async {
      final plan = session(expenses: []);
      plan.saveExpense(
        name: '保有期間外の予定',
        month: const YearMonth(2034, 9),
        amountYen: 100,
      );
      final id = plan.plannedExpenses.single.id;
      plan.apply(conditions(ownership: 60, age: 60));
      await pumpApp(tester, plan, scale: 3);
      await openList(tester);
      await edit(tester, id);
      expect(find.text('2034年9月'), findsOneWidget);
      await tapVisible(tester, find.text('この予定を削除'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('confirm-delete-expense')),
      );
      expect(plan.plannedExpenses, isEmpty);
      expect(find.text('予定費を削除しました'), findsOneWidget);
      safeLayout(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('予定費はまだありません'));
      await tester.pumpAndSettle();
      safeLayout(tester);
      await add(tester);
      await enterExpense(tester, '無料点検', '0');
      await save(tester);
      expect(find.text('予定費を追加しました'), findsOneWidget);
      safeLayout(tester);
    },
  );

  testWidgets(
    'mixed year sums only included rows and extending restores the annual total',
    (tester) async {
      final plan = session(expenses: []);
      plan.saveExpense(
        name: '期間内',
        month: const YearMonth(2030, 4),
        amountYen: 100,
      );
      plan.saveExpense(
        name: '期間外',
        month: const YearMonth(2030, 5),
        amountYen: 200,
      );
      plan.apply(conditions(ownership: 60, age: 60));
      await pumpApp(tester, plan);
      await openList(tester);
      expect(find.text('合計 100円'), findsOneWidget);
      expect(find.text('現在の保有期間外'), findsOneWidget);
      expect(find.text('現在の試算対象なし'), findsNothing);
      await back(tester);
      plan.apply(conditions());
      await openList(tester);
      expect(find.text('合計 300円'), findsOneWidget);
      expect(find.text('現在の保有期間外'), findsNothing);
    },
  );

  testWidgets(
    'empty -> add duplicate zero -> edit by ID -> delete cancel and confirm -> empty',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        expenses: [],
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      await pumpApp(tester, plan);
      await openList(tester);
      expect(find.text('予定費はまだありません'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        calls.reset();
        await add(tester);
        expect(tester.widget<TextField>(field('name')).controller!.text, '');
        expect(tester.widget<TextField>(field('amount')).controller!.text, '');
        expect(find.text('2026年9月'), findsOneWidget);
        expect(find.text('この予定を削除'), findsNothing);
        await enterExpense(tester, '　無料点検 ', '0');
        expect((calls.timeline, calls.reserve), (0, 0));
        await save(tester);
        expect(find.text('予定費を追加しました'), findsOneWidget);
        expect((calls.timeline, calls.reserve), (1, 1));
        expect(find.text('合計 0円'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      final ids = plan.plannedExpenses.map((e) => e.id).toList();
      expect(ids[0], isNot(ids[1]));
      await edit(tester, ids[0]);
      await enterExpense(tester, '有料点検', '1000');
      calls.reset();
      await save(tester);
      expect((calls.timeline, calls.reserve), (1, 1));
      expect(plan.plannedExpenses.first.id, ids[0]);
      expect(plan.plannedExpenses.last.name, '無料点検');
      expect(find.text('合計 1,000円'), findsOneWidget);
      expect(find.text('予定費を更新しました'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      for (final id in ids) {
        await edit(tester, id);
        calls.reset();
        final before = plan.plannedExpenses;
        await tapVisible(tester, find.text('この予定を削除'));
        await tapVisible(tester, find.text('キャンセル'));
        expect(plan.plannedExpenses, same(before));
        expect(find.byType(PlannedExpenseEditor), findsOneWidget);
        expect((calls.timeline, calls.reserve), (0, 0));
        await tapVisible(tester, find.text('この予定を削除'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('confirm-delete-expense')),
        );
        expect((calls.timeline, calls.reserve), (1, 1));
        expect(find.text('予定費を削除しました'), findsOneWidget);
        expect(plan.plannedExpenses.any((e) => e.id == id), isFalse);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(find.text('予定費はまだありません'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '予定費を追加'), findsOneWidget);
      safeLayout(tester);
    },
  );

  testWidgets(
    'explicit edit only; scroll, draft, Back, month cancellation and normalized no-op never calculate',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      await pumpApp(tester, plan);
      await openList(tester);
      calls.reset();
      final original = plan.plannedExpenses;
      await tapVisible(tester, find.text('12Vバッテリー'));
      expect(find.byType(PlannedExpenseEditor), findsNothing);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlannedExpenseEditor), findsNothing);
      final e = original.first;
      for (final androidBack in [false, true]) {
        await edit(tester, e.id);
        await enterExpense(tester, '破棄する', '999999');
        expect(plan.plannedExpenses, same(original));
        if (androidBack) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await back(tester);
        }
        expect(plan.plannedExpenses, same(original));
        expect(find.byType(AlertDialog), findsNothing);
      }
      await edit(tester, e.id);
      await tapVisible(tester, field('month'));
      await tapVisible(tester, find.byKey(const ValueKey('expense-year-2026')));
      expect(find.byKey(const ValueKey('expense-month-8')), findsNothing);
      expect(find.byKey(const ValueKey('expense-month-9')), findsOneWidget);
      Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.text('2027年4月'), findsOneWidget);
      await enterExpense(tester, '　${e.name} ', '${e.amountYen}');
      await save(tester);
      expect(plan.plannedExpenses, same(original));
      expect(find.text('予定費を更新しました'), findsNothing);
      expect((calls.timeline, calls.reserve), (0, 0));
    },
  );

  testWidgets(
    'month picker exposes inclusive boundaries and save validation blocks invalid input',
    (tester) async {
      final plan = session(expenses: []);
      await pumpApp(tester, plan);
      await openList(tester);
      await add(tester);
      await save(tester);
      expect(find.byKey(const ValueKey('expense-error-name')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expense-error-amount')),
        findsOneWidget,
      );
      await enterExpense(tester, '車' * 41, '1000000001');
      await save(tester);
      expect(plan.plannedExpenses, isEmpty);
      expect(find.byKey(const ValueKey('expense-error-name')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expense-error-amount')),
        findsOneWidget,
      );
      await tapVisible(tester, field('month'));
      expect(find.byKey(const ValueKey('expense-year-2025')), findsNothing);
      expect(find.byKey(const ValueKey('expense-year-2041')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey('expense-year-2040')));
      expect(find.byKey(const ValueKey('expense-month-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('expense-month-5')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey('expense-month-4')));
      await enterExpense(tester, '車' * 40, '1000000000');
      await save(tester);
      expect(
        plan.plannedExpenses.single.plannedMonth,
        plan.ownershipTargetMonth,
      );
      expect(plan.plannedExpenses.single.amountYen, 1000000000);
      expect(plan.plannedExpenses.single.name.length, 40);
    },
  );

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      '360px scale $scale: outside rows, no-target year, zero year, editor, keyboard and notices',
      (tester) async {
        final plan = session(expenses: []);
        plan.saveExpense(
          name: '車' * 40,
          month: const YearMonth(2034, 9),
          amountYen: 1000000000,
        );
        plan.saveExpense(
          name: '無料点検',
          month: const YearMonth(2027, 4),
          amountYen: 0,
        );
        final outsideId = plan.plannedExpenses.first.id;
        plan.apply(conditions(ownership: 60, age: 60));
        await pumpApp(tester, plan, scale: scale);
        await openList(tester);
        for (final label in [
          '現在の保有期間外',
          '現在の試算対象なし',
          '合計 0円',
          '1,000,000,000円',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          safeLayout(tester);
        }
        expect(find.text('合計 1,000,000,000円'), findsNothing);
        await edit(tester, outsideId);
        expect(find.text('2034年9月'), findsOneWidget);
        await enterExpense(tester, '車' * 40, '1000000000');
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await save(tester);
        expect(find.byType(PlannedExpenseEditor), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('expense-error-month')),
        );
        await tester.pumpAndSettle();
        safeLayout(tester);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tapVisible(tester, field('month'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('expense-year-2026')),
        );
        await tapVisible(tester, find.byKey(const ValueKey('expense-month-9')));
        await save(tester);
        expect(plan.plannedExpenses.first.id, outsideId);
        expect(find.text('現在の保有期間外'), findsNothing);
        expect(find.text('予定費を更新しました'), findsOneWidget);
        safeLayout(tester);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await edit(tester, outsideId);
        await tapVisible(tester, find.text('この予定を削除'));
        safeLayout(tester);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('confirm-delete-expense')),
        );
        safeLayout(tester);
      },
    );
  }

  testWidgets(
    'CRUD results reach Step 8/9; first visit feedback then normal revisit without calculations',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        expenses: [],
        initial: conditions(fund: 0),
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      await pumpApp(tester, plan);
      await openList(tester);
      await add(tester);
      await enterExpense(tester, '車検', '1000000');
      await save(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await back(tester);
      calls.reset();
      for (final first in [true, false]) {
        await tapVisible(tester, find.text('未来タイムラインを見る'));
        expect(find.text('車検'), findsOneWidget);
        expect(find.text('年間予定費 1,000,000円'), findsOneWidget);
        expect(
          tester
              .widget<FutureTimelineScreen>(find.byType(FutureTimelineScreen))
              .updatePending,
          first,
        );
        expect(plan.timelinePending, isFalse);
        expect(plan.reservePending, first);
        await back(tester);
        await tapVisible(tester, find.text('詳しく見る'));
        expect(find.text('月 1,000,000円'), findsNWidgets(2));
        expect(
          tester
              .widget<RepairReserveScreen>(find.byType(RepairReserveScreen))
              .updatePending,
          first,
        );
        expect(plan.reservePending, isFalse);
        tester.platformDispatcher.textScaleFactorTestValue = 3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await back(tester);
      }
      expect((calls.timeline, calls.reserve), (0, 0));
      expect(find.byType(PlannedExpensesScreen), findsNothing);
    },
  );
}
