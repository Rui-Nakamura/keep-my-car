import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expenses_screen.dart';

import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';

import 'plan_test_support.dart';

void main() {
  testWidgets(
    'Home passes no saved expenses for reached target without retention notice',
    (tester) async {
      final plan = session(
        initial: conditions(ownership: 55),
        birth: const YearMonth(1970, 4),
        reference: const YearMonth(2026, 10),
        expenses: [],
      );
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('未来タイムラインを見る'));
      await tester.tap(find.text('未来タイムラインを見る'));
      await tester.pumpAndSettle();
      final screen = tester.widget<FutureTimelineScreen>(
        find.byType(FutureTimelineScreen),
      );
      expect(screen.hasSavedPlannedExpenses, isFalse);
      expect(find.text('保有目標に到達しています'), findsOneWidget);
      expect(find.text('設定している保有目標：55歳・2025年4月'), findsOneWidget);
      expect(find.textContaining('登録済みの予定費'), findsNothing);
      expect(find.textContaining('「愛車予定費」'), findsNothing);
      expect(screen.years.length, 1);
      expect(screen.years.single.year, 2026);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'past target retains saved expenses, list access and no navigation saves',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        initial: conditions(ownership: 55),
        birth: const YearMonth(1970, 4),
        reference: const YearMonth(2026, 10),
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      final stored = plan.plannedExpenses;
      final original = List.of(stored);
      final cached = plan.timeline;
      final reserve = plan.reserveResult;
      final repository = TestRepository(Loaded(sampleSnapshot(plan)));
      calls.reset();
      await tester.pumpWidget(
        KeepMyCarApp(
          repository: repository,
          now: () => DateTime(2026, 10),
          sessionFactory: (_, _) => plan,
        ),
      );
      await tester.pumpAndSettle();
      expect(stored.length, greaterThan(1));
      final link = find.text('未来タイムラインを見る');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      final screen = tester.widget<FutureTimelineScreen>(
        find.byType(FutureTimelineScreen),
      );
      expect(screen.years, same(cached));
      expect(screen.ownershipTargetReached, isTrue);
      expect(screen.hasSavedPlannedExpenses, isTrue);
      expect(find.text('登録済みの予定費は削除されていません。「愛車予定費」から確認できます。'), findsOneWidget);
      expect(screen.ownershipTargetAge, 55);
      expect(screen.ownershipTargetMonth, const YearMonth(2025, 4));
      expect(find.text('設定している保有目標：55歳・2025年4月'), findsOneWidget);
      expect(find.text('保有目標：56歳・2025年4月'), findsNothing);
      expect(find.byKey(const ValueKey('timeline-year-2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-year-2025')), findsNothing);
      expect(find.byKey(const ValueKey('timeline-year-2027')), findsNothing);
      expect(find.text('オーナー 56歳'), findsOneWidget);
      expect(find.text('想定走行距離 約45,000km'), findsOneWidget);
      expect(find.text('10月時点'), findsOneWidget);
      expect(find.text('現在'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(find.text('保有目標を見直す'), findsNothing);
      expect(cached.single.totalYen, 0);
      expect(cached.single.expenses, isEmpty);
      for (final expense in original) {
        expect(find.text(expense.name), findsNothing);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final listLink = find.text('予定費を確認する');
      await tester.ensureVisible(listLink);
      await tester.tap(listLink);
      await tester.pumpAndSettle();
      expect(find.byType(PlannedExpensesScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, '愛車予定費'), findsOneWidget);
      for (final expense in original) {
        expect(find.text(expense.name), findsWidgets);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(plan.plannedExpenses, same(stored));
      expect(plan.plannedExpenses, orderedEquals(original));
      expect(plan.timeline, same(cached));
      expect(plan.reserveResult, same(reserve));
      expect((calls.timeline, calls.reserve), (0, 0));
      expect(repository.saves, isEmpty);
      expect(repository.discards, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home passes formal months and cached timeline without recalculating',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        initial: conditions(ownership: 56, age: 56),
        birth: const YearMonth(1970, 12),
        reference: const YearMonth(2026, 10),
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      final cached = plan.timeline;
      calls.reset();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      final link = find.text('未来タイムラインを見る');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      final screen = tester.widget<FutureTimelineScreen>(
        find.byType(FutureTimelineScreen),
      );
      expect(screen.years, same(cached));
      expect(screen.referenceMonth, plan.referenceMonth);
      expect(screen.ownershipTargetMonth, const YearMonth(2026, 12));
      expect(screen.ownershipTargetAge, 56);
      expect(screen.ownershipTargetReached, isFalse);
      expect(screen.hasSavedPlannedExpenses, isTrue);
      expect(find.text('12月時点の見込み'), findsOneWidget);
      expect(find.text('現在'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect((calls.timeline, calls.reserve), (0, 0));
      expect(plan.timeline, same(cached));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home passes supplied funds and converts target age to birth month',
    (tester) async {
      final plan = session(
        initial: conditions(fund: 120, reserve: 1000, age: 60),
        birth: const YearMonth(1980, 11),
        reference: const YearMonth(2040, 10),
      );
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await openReserveForTest(tester);
      await tester.pumpAndSettle();
      expect(
        (plan.reserveResult as RepairReserveSuccess).repairIncludedMonthlyYen,
        440,
      );
      expect(find.text('60歳まで'), findsOneWidget);
      expect(find.text('月 440円'), findsOneWidget);
      expect(find.text('＋440円／月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  const destinations = [
    (
      '未来タイムラインを見る',
      '未来タイムライン',
      [
        '保有目標までの計画',
        '2026年',
        'オーナー 56歳',
        '車齢 8年',
        '想定走行距離 約45,000km',
        '12Vバッテリー',
        '4月',
        '80,000円',
      ],
    ),
    ('すべて見る', '愛車予定費', ['6件の予定']),
    (
      '詳しく見る',
      '大型修理への備え',
      [
        '保有目標',
        '70歳まで',
        '備え目標',
        '65歳まで',
        '想定大型修理',
        '2,000,000円',
        '予定費のみ',
        '月 11,341円',
        '大型修理込み',
        '月 29,808円',
        '大型修理への備え分',
        '＋18,467円／月',
        '※大型修理の発生時期を予測するものではありません。',
      ],
    ),
    (
      '設定',
      '計画設定',
      ['車・所有計画', '現在走行距離', '年間走行距離', '資金計画', '現在の愛車専用資金', '大型修理予備費', 'この試算に反映'],
    ),
  ];

  for (final scale in [1.0, 3.0]) {
    for (final destination in destinations) {
      testWidgets(
        '${destination.$2}: navigation, content and back at 360px / $scale',
        (tester) async {
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
              home: testApp(),
            ),
          );
          await tester.pumpAndSettle();

          if (destination.$1 == '詳しく見る') {
            await openReserveForTest(tester);
          } else {
            final link = find.text(destination.$1);
            await tester.ensureVisible(link);
            await tester.pumpAndSettle();
            await tester.tap(link);
          }
          await tester.pumpAndSettle();
          expect(find.byType(HomeScreen), findsNothing);
          expect(find.widgetWithText(AppBar, destination.$2), findsOneWidget);
          expect(find.byType(BackButton), findsOneWidget);
          for (final label in destination.$3) {
            // Month-only expense labels are scoped to their calendar year.
            final value = destination.$2 == '未来タイムライン' && label == '4月'
                ? find.descendant(
                    of: find.byKey(const ValueKey('timeline-year-2027')),
                    matching: find.text(label),
                  )
                : find.text(label);
            expect(value, findsOneWidget);
            await tester.ensureVisible(value);
            await tester.pumpAndSettle();
            final rect = tester.getRect(value);
            expect(rect.left, greaterThanOrEqualTo(20));
            expect(rect.right, lessThanOrEqualTo(340));
          }
          for (final element in find.byType(RichText).evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
            expect(paragraph.didExceedMaxLines, isFalse);
          }
          for (final state in tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          )) {
            expect(state.position.axis, Axis.vertical);
          }
          expect(find.byType(BottomNavigationBar), findsNothing);
          expect(find.byType(NavigationRail), findsNothing);
          expect(find.byType(Drawer), findsNothing);
          expect(
            find.byType(TextField),
            destination.$2 == '計画設定' ? findsNWidgets(4) : findsNothing,
          );
          expect(tester.takeException(), isNull);
          if (scale == 1.0) {
            await tester.tap(find.byType(BackButton));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(
            tester.widget<HomeScreen>(find.byType(HomeScreen)),
            isA<HomeScreen>(),
          );
          expect(find.byType(AppBar), findsNothing);
          for (final label in ['70歳まで乗る計画', 'あと13年7か月']) {
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
