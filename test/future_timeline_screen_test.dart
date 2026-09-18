import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/theme/app_theme.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/timeline/future_timeline_calculator.dart';

import 'plan_test_support.dart';

import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';

int _nextExpenseId = 1;

PlannedExpense expense(String name, int year, int month, int amount) =>
    PlannedExpense(
      id: _nextExpenseId++,
      name: name,
      plannedMonth: YearMonth(year, month),
      amountYen: amount,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );

Finder yearSection(int year) => find.byKey(ValueKey('timeline-year-$year'));
Finder inYear(int year, String label) =>
    find.descendant(of: yearSection(year), matching: find.text(label));

Future<void> pumpTimeline(
  WidgetTester tester,
  List<PlannedExpense> expenses, {
  int age = 56,
  double scale = 1,
  int year = 2026,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FutureTimelineScreen(
        years: calculateFutureTimeline(
          currentYear: year,
          currentOwnerAge: age,
          currentCarAge: 8,
          currentMileageKm: 45000,
          annualMileageKm: 4000,
          plannedExpenses: expenses,
        ),
      ),
    ),
  );
}

void expectSafeLayout(WidgetTester tester) {
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
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'ten empty years keep all yearly values and only first current marker',
    (tester) async {
      await pumpTimeline(tester, []);
      const expected = [
        (2026, '56歳', '車齢8年', '約45,000km'),
        (2027, '57歳', '車齢9年', '約49,000km'),
        (2028, '58歳', '車齢10年', '約53,000km'),
        (2029, '59歳', '車齢11年', '約57,000km'),
        (2030, '60歳', '車齢12年', '約61,000km'),
        (2031, '61歳', '車齢13年', '約65,000km'),
        (2032, '62歳', '車齢14年', '約69,000km'),
        (2033, '63歳', '車齢15年', '約73,000km'),
        (2034, '64歳', '車齢16年', '約77,000km'),
        (2035, '65歳', '車齢17年', '約81,000km'),
      ];
      double previousY = -1;
      for (final row in expected) {
        for (final label in ['${row.$1}年', row.$2, row.$3, row.$4, '予定費なし']) {
          expect(inYear(row.$1, label), findsOneWidget);
        }
        final y = tester.getTopLeft(yearSection(row.$1)).dy;
        expect(y, greaterThan(previousY));
        previousY = y;
      }
      expect(find.text('予定費なし'), findsNWidgets(10));
      expect(find.textContaining('年間予定費'), findsNothing);
      expect(find.text('現在'), findsOneWidget);
      expect(inYear(2026, '現在'), findsOneWidget);
      expect(find.text('2025年'), findsNothing);
      expect(find.text('2036年'), findsNothing);
      expect(find.text('2035年').hitTestable(), findsNothing);
      await tester.scrollUntilVisible(find.text('2035年'), 500);
      await tester.pumpAndSettle();
      expect(find.text('2035年').hitTestable(), findsOneWidget);
      expectSafeLayout(tester);
    },
  );

  for (final age in [59, 64, 69, 74]) {
    testWidgets('only milestone ${age + 1} is emphasized among adjacent ages', (
      tester,
    ) async {
      await pumpTimeline(tester, [], age: age);
      final before = tester.widget<Text>(inYear(2026, '$age歳')).style!;
      final milestone = tester.widget<Text>(inYear(2027, '${age + 1}歳')).style!;
      final after = tester.widget<Text>(inYear(2028, '${age + 2}歳')).style!;
      expect(
        milestone.fontWeight!.value,
        greaterThan(before.fontWeight!.value),
      );
      expect(after, before);
      for (final label in ['定年', '年金', '免許返納', '高齢者']) {
        expect(find.textContaining(label), findsNothing);
      }
    });
  }

  testWidgets(
    'sorts unsorted input stably, totals by year, does not mutate input',
    (tester) async {
      final input = [
        expense('翌年', 2028, 6, 200000),
        expense('同月Z', 2027, 10, 30000),
        expense('春', 2027, 4, 100000),
        expense('同月A', 2027, 10, 20000),
      ];
      final original = List<PlannedExpense>.of(input);
      await pumpTimeline(tester, input);
      const labels = ['春', '同月Z', '同月A', '翌年'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i - 1])).dy,
          lessThan(tester.getTopLeft(find.text(labels[i])).dy),
        );
      }
      for (final label in ['春', '同月Z', '同月A', '2027年4月', '年間予定費 150,000円']) {
        expect(inYear(2027, label), findsOneWidget);
      }
      expect(inYear(2027, '2027年10月'), findsNWidgets(2));
      expect(inYear(2028, '翌年'), findsOneWidget);
      expect(inYear(2028, '年間予定費 200,000円'), findsOneWidget);
      expect(input, orderedEquals(original));
      expectSafeLayout(tester);
    },
  );

  testWidgets(
    'empty, single zero, mixed paid and zero, multiple zero years differ',
    (tester) async {
      await pumpTimeline(tester, [
        expense('無料点検', 2027, 1, 0),
        expense('12V点検', 2028, 1, 0),
        expense('タイヤ交換', 2028, 2, 100000),
        expense('無料診断A', 2029, 1, 0),
        expense('無料診断B', 2029, 2, 0),
      ]);
      expect(inYear(2026, '予定費なし'), findsOneWidget);
      expect(
        find.descendant(
          of: yearSection(2026),
          matching: find.textContaining('年間予定費'),
        ),
        findsNothing,
      );
      expect(inYear(2027, '無料点検'), findsOneWidget);
      expect(inYear(2027, '年間予定費 0円'), findsOneWidget);
      for (final label in [
        '12V点検',
        'タイヤ交換',
        '0円',
        '100,000円',
        '年間予定費 100,000円',
      ]) {
        expect(inYear(2028, label), findsOneWidget);
      }
      for (final label in ['無料診断A', '無料診断B', '年間予定費 0円']) {
        expect(inYear(2029, label), findsOneWidget);
      }
      expect(inYear(2029, '0円'), findsNWidgets(2));
      for (final year in [2027, 2028, 2029]) {
        expect(inYear(year, '予定費なし'), findsNothing);
      }
    },
  );

  testWidgets('fixed year boundaries include January and final December only', (
    tester,
  ) async {
    await pumpTimeline(tester, [
      expense('範囲後', 2036, 1, 900000),
      expense('最後', 2035, 12, 200),
      expense('範囲前', 2025, 12, 800000),
      expense('最初', 2026, 1, 100),
    ]);
    expect(find.text('範囲前'), findsNothing);
    expect(find.text('範囲後'), findsNothing);
    expect(inYear(2026, '最初'), findsOneWidget);
    expect(inYear(2026, '2026年1月'), findsOneWidget);
    expect(inYear(2026, '年間予定費 100円'), findsOneWidget);
    expect(inYear(2035, '最後'), findsOneWidget);
    expect(inYear(2035, '2035年12月'), findsOneWidget);
    expect(inYear(2035, '年間予定費 200円'), findsOneWidget);
  });

  testWidgets(
    'supplied base year is used instead of a fixed year or device date',
    (tester) async {
      await pumpTimeline(tester, [], year: 2040);
      expect(inYear(2040, '現在'), findsOneWidget);
      expect(find.text('2049年'), findsOneWidget);
      expect(find.text('2026年'), findsNothing);
      expect(find.text('2050年'), findsNothing);
    },
  );

  testWidgets(
    '360px scale 3 long name and 3 million safely reflow through final year',
    (tester) async {
      const name = 'フロント・リアブレーキディスクおよびパッド一式交換';
      await pumpTimeline(tester, [expense(name, 2035, 12, 3000000)], scale: 3);
      for (final label in [
        '2035年',
        '65歳',
        '車齢17年',
        '約81,000km',
        name,
        '2035年12月',
        '3,000,000円',
        '年間予定費 3,000,000円',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expectSafeLayout(tester);
        final widget = tester.widget<Text>(find.text(label));
        expect(widget.maxLines, isNull);
        expect(widget.overflow, isNot(TextOverflow.ellipsis));
      }
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(name), matching: find.byType(RichText)),
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: name.length),
      );
      expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
      expect(find.byType(FittedBox), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(
        tester.getTopLeft(find.text('3,000,000円')).dy,
        greaterThan(tester.getTopLeft(find.text('2035年12月')).dy),
      );
    },
  );

  for (final reference in [
    const YearMonth(2030, 3),
    const YearMonth(2030, 4),
    const YearMonth(2030, 5),
  ]) {
    testWidgets(
      'Home computes completed years at $reference and keeps stored mileage',
      (tester) async {
        await tester.pumpWidget(
          KeepMyCarApp(
            session: session(
              initial: conditions(mileage: 12345, annual: 2000),
              birth: const YearMonth(1970, 4),
              reference: reference,
              registration: const YearMonth(2020, 4),
            ),
          ),
        );
        final link = find.text('未来タイムラインを見る');
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(inYear(2030, '現在'), findsOneWidget);
        expect(
          inYear(2030, reference.month == 3 ? '59歳' : '60歳'),
          findsOneWidget,
        );
        expect(
          inYear(2030, reference.month == 3 ? '車齢9年' : '車齢10年'),
          findsOneWidget,
        );
        expect(inYear(2030, '約12,345km'), findsOneWidget);
        expect(inYear(2031, '約14,345km'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
