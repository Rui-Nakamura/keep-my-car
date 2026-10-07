import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/display_format.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expense_editor.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expenses_screen.dart';
import 'package:keep_my_car/features/settings/presentation/plan_settings_screen.dart';
import 'package:keep_my_car/app/screen_success_feedback.dart';

import 'persistence_app_support.dart';
import 'plan_test_support.dart';
import 'app/plan_summary_test.dart' show expense;

Future<void> tapLabel(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void expectNoTotals() {
  for (final label in ['70歳までの予定費', '次の予定費', 'これからの予定費', '来年', '5年間', '0円']) {
    expect(find.text(label), findsNothing);
  }
}

void main() {
  testWidgets(
    'Golden Home prioritizes ownership with formal expense summaries',
    (tester) async {
      final plan = session();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      for (final label in [
        '70歳まで乗る計画',
        'あと13年7か月',
        '保有目標時の車齢21年',
        '約99,000km',
        '70歳までの予定費',
        '2,550,000円',
        '登録している予定費の合計です',
        '次の予定費',
        '2027年4月',
        '12Vバッテリー',
        'これからの予定費',
        '来年',
        '5年間',
        '未来タイムラインを見る',
        '＋ 予定費を追加',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('80,000円'), findsNWidgets(2));
      expect(
        find.text(formatYen(plan.fiveYearExpensesTotalYen)),
        findsOneWidget,
      );
      expect(plan.ownershipTargetMileageKm, 99333);
      final target = tester.widget<Text>(find.text('70歳まで乗る計画'));
      final total = tester.widget<Text>(find.text('2,550,000円'));
      expect(target.style!.fontSize, greaterThan(total.style!.fontSize!));
      expect(find.widgetWithText(FilledButton, '未来タイムラインを見る'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '＋ 予定費を追加'), findsOneWidget);
      for (final label in [
        '大型修理への備え',
        '詳しく見る',
        '予定費のみ',
        '大型修理込み',
        '備え分',
        '前回の試算より',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byType(Card), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    },
  );

  for (final entry in [
    (const YearMonth(2026, 9), 163, 'あと13年7か月'),
    (const YearMonth(2039, 9), 7, 'あと7か月'),
    (const YearMonth(2030, 4), 120, 'あと10年'),
    (const YearMonth(2040, 4), 0, '今月が保有目標です'),
  ]) {
    testWidgets('remaining boundary ${entry.$2} months', (tester) async {
      final plan = session(reference: entry.$1, expenses: []);
      expect(plan.monthsUntilOwnershipTarget, entry.$2);
      expect(plan.ownershipTargetReached, isFalse);
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      expect(find.text(entry.$3), findsOneWidget);
      expect(find.text('＋ 予定費を追加'), findsOneWidget);
    });
  }

  for (final entry in [
    (99333, '約99,000km'),
    (99600, '約100,000km'),
    (999, '約999km'),
    (0, '約0km'),
  ]) {
    test('Home distance ${entry.$1} preserves detailed formatter', () {
      expect(formatHomeMileageKm(entry.$1), entry.$2);
      expect(formatKm(entry.$1), '${formatNumber(entry.$1)}km');
    });
  }

  testWidgets('state A retains plan and direct add, hides zero totals', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(session: session(expenses: [])));
    await tester.pumpAndSettle();
    expect(find.text('予定費はまだありません'), findsOneWidget);
    expect(find.text('70歳まで乗る計画'), findsOneWidget);
    expect(find.text('約99,000km'), findsOneWidget);
    expect(find.text('未来タイムラインを見る'), findsOneWidget);
    expectNoTotals();
    await tapLabel(tester, '＋ 予定費を追加');
    expect(find.byType(PlannedExpenseEditor), findsOneWidget);
    expect(find.byType(PlannedExpensesScreen), findsNothing);
    expect(
      tester
          .widget<PlannedExpenseEditor>(find.byType(PlannedExpenseEditor))
          .expense,
      isNull,
    );
  });

  for (final expenses in [
    [expense(1, 2026, 8, 10)],
    [expense(1, 2040, 5, 10)],
    [expense(1, 2026, 8, 10), expense(2, 2040, 5, 20)],
  ]) {
    testWidgets(
      'state B saved out-of-range expenses ${expenses.length}/${expenses.first.plannedMonth}',
      (tester) async {
        await tester.pumpWidget(testApp(session: session(expenses: expenses)));
        await tester.pumpAndSettle();
        expect(find.text('保有目標までの予定費はありません'), findsOneWidget);
        expect(find.text('予定費はまだありません'), findsNothing);
        expect(find.text('＋ 予定費を追加'), findsOneWidget);
        expectNoTotals();
        await tapLabel(tester, '予定費を確認する');
        expect(find.byType(PlannedExpensesScreen), findsOneWidget);
        expect(find.text('${expenses.length}件の予定'), findsOneWidget);
      },
    );
  }

  testWidgets('same month uses first original item and total including zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        session: session(
          expenses: [
            expense(1, 2028, 1, 900),
            expense(2, 2027, 4, 400000),
            expense(3, 2027, 4, 180000),
            expense(4, 2027, 4, 0),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('expense 2 ほか2件'), findsOneWidget);
    expect(find.text('580,000円'), findsNWidgets(2));
  });

  testWidgets('zero-cost item remains an expense', (tester) async {
    await tester.pumpWidget(
      testApp(session: session(expenses: [expense(1, 2027, 1, 0)])),
    );
    await tester.pumpAndSettle();
    expect(find.text('次の予定費'), findsOneWidget);
    expect(find.text('expense 1'), findsOneWidget);
    expect(find.text('0円'), findsNWidgets(4));
    expect(find.text('予定費はまだありません'), findsNothing);
  });

  for (final saved in [false, true]) {
    testWidgets('reached target prioritizes review with saved=$saved', (
      tester,
    ) async {
      final plan = session(
        reference: const YearMonth(2040, 5),
        expenses: saved ? [expense(1, 2040, 4, 10)] : [],
      );
      expect(plan.ownershipTargetReached, isTrue);
      expect(plan.monthsUntilOwnershipTarget, -1);
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      expect(find.text('保有目標に到達しています'), findsOneWidget);
      expect(find.text('設定していた保有目標は 2040年4月でした'), findsOneWidget);
      expect(find.text('未来タイムラインを見る'), findsOneWidget);
      expect(find.text('＋ 予定費を追加'), findsNothing);
      expect(find.text('70歳まで乗る計画'), findsNothing);
      expect(find.textContaining('車齢'), findsNothing);
      expect(find.textContaining('想定走行距離'), findsNothing);
      expectNoTotals();
      expect(find.text('予定費を確認する'), saved ? findsOneWidget : findsNothing);
      if (saved) {
        await tapLabel(tester, '予定費を確認する');
        expect(find.byType(PlannedExpensesScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      await tapLabel(tester, '保有目標を見直す');
      expect(find.byType(PlanSettingsScreen), findsOneWidget);
    });
  }

  for (final change in ['timeline', 'reserve', 'both']) {
    testWidgets('HomeUpdate $change retains enum and changes Home wording', (
      tester,
    ) async {
      final plan = session();
      plan.apply(
        conditions(
          annual: change == 'reserve' ? 4000 : 6000,
          fund: change == 'timeline' ? 500000 : 1000000,
        ),
      );
      expect(plan.homeUpdate, HomeUpdate.values.byName(change));
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      expect(
        find.text('未来タイムラインを更新しました'),
        change == 'reserve' ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets(
    'direct add returns Home, recalculates once, SnackBar without HomeUpdate or new outline',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        expenses: [],
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      calls.reset();
      final notification = tester
          .widget<ScreenSuccessFeedback>(find.byType(ScreenSuccessFeedback))
          .notificationId;
      await tapLabel(tester, '＋ 予定費を追加');
      await tester.enterText(
        find.byKey(const ValueKey('expense-input-name')),
        '車検',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expense-input-amount')),
        '1000000',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('save-expense')));
      await tester.tap(find.byKey(const ValueKey('save-expense')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('車検'), findsOneWidget);
      expect(find.text('予定費を追加しました'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-update')), findsNothing);
      expect(plan.homeUpdate, isNull);
      expect(plan.timelinePending, isTrue);
      expect(plan.reservePending, isTrue);
      expect((calls.timeline, calls.reserve), (1, 1));
      expect(
        tester
            .widget<ScreenSuccessFeedback>(find.byType(ScreenSuccessFeedback))
            .notificationId,
        notification,
      );
    },
  );

  for (final scale in [1.0, 3.0]) {
    for (final state in ['normal', 'A', 'B', 'reached']) {
      testWidgets('Home $state 360px scale $scale wraps and exposes controls', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final plan = session(
          initial: conditions(ownership: 100, age: 100),
          reference: state == 'reached' ? const YearMonth(2070, 5) : null,
          expenses: state == 'A'
              ? []
              : state == 'B'
              ? [expense(1, 2026, 8, 10)]
              : null,
        );
        await tester.pumpWidget(testApp(session: plan));
        await tester.pumpAndSettle();
        for (final element in find.byType(RichText).evaluate()) {
          final p = element.renderObject! as RenderParagraph;
          final rect = p.localToGlobal(Offset.zero) & p.size;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(p.didExceedMaxLines, isFalse);
          expect(p.overflow, isNot(TextOverflow.ellipsis));
        }
        for (final label in [
          '愛車名を編集',
          '設定',
          '未来タイムラインを見る',
          if (state != 'reached') '＋ 予定費を追加',
          if (state == 'reached') '保有目標を見直す',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
