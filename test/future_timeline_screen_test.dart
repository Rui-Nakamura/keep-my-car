import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/app/theme/app_theme.dart';
import 'package:keep_my_car/app/display_format.dart';
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

Future<List<TimelineYearData>> pumpTimeline(
  WidgetTester tester,
  List<PlannedExpense> expenses, {
  int age = 56,
  int targetAge = 70,
  double scale = 1,
  int year = 2026,
  YearMonth? reference,
  YearMonth? target,
  YearMonth? birth,
  YearMonth? registration,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final referenceMonth = reference ?? YearMonth(year, 1);
  final ownershipTargetMonth = target ?? YearMonth(year + 9, 12);
  final targetPlan = session(
    initial: conditions(ownership: targetAge),
    birth: YearMonth(
      ownershipTargetMonth.year - targetAge,
      ownershipTargetMonth.month,
    ),
    reference: referenceMonth,
    expenses: expenses,
  );
  final years = calculateFutureTimeline(
    referenceMonth: referenceMonth,
    birthMonth: birth ?? YearMonth(year - age, 1),
    firstRegistrationMonth: registration ?? YearMonth(year - 8, 1),
    ownershipTargetMonth: ownershipTargetMonth,
    currentMileageKm: 45000,
    annualMileageKm: 4000,
    plannedExpenses: expenses,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FutureTimelineScreen(
        years: years,
        referenceMonth: referenceMonth,
        ownershipTargetMonth: ownershipTargetMonth,
        ownershipTargetAge: targetPlan.conditions.ownershipTargetAge,
        ownershipTargetReached: targetPlan.ownershipTargetReached,
        hasSavedPlannedExpenses: targetPlan.plannedExpenses.isNotEmpty,
      ),
    ),
  );
  return years;
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
  for (final scale in [1.0, 3.0]) {
    for (final testCase in const [
      (
        target: YearMonth(2025, 4),
        notice: true,
        label: '設定している保有目標：55歳・2025年4月',
      ),
      (target: YearMonth(2026, 10), notice: false, label: '今月が保有目標です'),
      (target: YearMonth(2026, 12), notice: false, label: '2026年12月'),
    ]) {
      testWidgets(
        'saved outside expense notice at ${testCase.target} scale $scale',
        (tester) async {
          final saved = [expense('計画外の保存済み予定費', 2041, 1, 100)];
          final original = List<PlannedExpense>.of(saved);
          final years = await pumpTimeline(
            tester,
            saved,
            reference: const YearMonth(2026, 10),
            target: testCase.target,
            targetAge: 55,
            scale: scale,
          );
          const notice = '登録済みの予定費は削除されていません。「愛車予定費」から確認できます。';
          expect(
            find.text(notice),
            testCase.notice ? findsOneWidget : findsNothing,
          );
          expect(find.text('登録済みの予定費は削除されていません。予定費一覧から確認できます。'), findsNothing);
          expect(find.text(testCase.label), findsOneWidget);
          expect(saved, orderedEquals(original));
          expect(years.single.expenses, isEmpty);
          expect(find.text('計画外の保存済み予定費'), findsNothing);
          if (testCase.notice) {
            await tester.ensureVisible(find.text(notice));
            await tester.pumpAndSettle();
            final text = tester.widget<Text>(find.text(notice));
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(notice),
                matching: find.byType(RichText),
              ),
            );
            for (var offset = 0; offset < notice.length; offset++) {
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                expect(box.left, greaterThanOrEqualTo(0));
                expect(
                  box.right,
                  lessThanOrEqualTo(paragraph.size.width + 0.1),
                );
                expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
              }
            }
          }
          expectSafeLayout(tester);
        },
      );
    }
  }
  for (final scale in [1.0, 3.0]) {
    for (final targetCase in const [
      (
        month: YearMonth(2040, 4),
        reached: false,
        current: false,
        last: 2040,
        label: '2040年4月',
        age: 70,
      ),
      (
        month: YearMonth(2026, 12),
        reached: false,
        current: false,
        last: 2026,
        label: '2026年12月',
        age: 56,
      ),
      (
        month: YearMonth(2026, 10),
        reached: false,
        current: true,
        last: 2026,
        label: '保有目標：2026年10月',
        age: 56,
      ),
      (
        month: YearMonth(2026, 4),
        reached: true,
        current: false,
        last: 2026,
        label: '設定している保有目標：56歳・2026年4月',
        age: 56,
      ),
      (
        month: YearMonth(2025, 4),
        reached: true,
        current: false,
        last: 2026,
        label: '設定している保有目標：55歳・2025年4月',
        age: 55,
      ),
    ]) {
      testWidgets(
        'ownership target ${targetCase.month} at 360px scale $scale',
        (tester) async {
          await pumpTimeline(
            tester,
            [],
            reference: const YearMonth(2026, 10),
            target: targetCase.month,
            targetAge: targetCase.age,
            scale: scale,
          );
          expect(
            find.text('保有目標に到達しています'),
            targetCase.reached ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('今月が保有目標です'),
            targetCase.current ? findsOneWidget : findsNothing,
          );
          expect(
            find.byIcon(Icons.flag_outlined),
            targetCase.reached ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('保有目標'),
            !targetCase.reached && !targetCase.current
                ? findsOneWidget
                : findsNothing,
          );
          expect(find.text(targetCase.label), findsOneWidget);
          if (!targetCase.reached) {
            expect(inYear(targetCase.last, targetCase.label), findsOneWidget);
            expect(
              find.descendant(
                of: yearSection(targetCase.last),
                matching: find.byIcon(Icons.flag_outlined),
              ),
              findsOneWidget,
            );
          }
          expect(yearSection(targetCase.last + 1), findsNothing);
          expect(yearSection(2025), findsNothing);
          if (targetCase.last == 2026) {
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'timeline-year-',
                    ),
              ),
              findsOneWidget,
            );
          }
          const retained = '登録済みの予定費は削除されていません。「愛車予定費」から確認できます。';
          expect(find.text(retained), findsNothing);
          expect(find.textContaining('「愛車予定費」'), findsNothing);
          expect(find.text('保有目標を見直す'), findsNothing);
          final labels = [
            targetCase.label,
            if (targetCase.current) '今月が保有目標です',
            if (targetCase.reached) '保有目標に到達しています',
            if (!targetCase.reached && !targetCase.current) '保有目標',
          ];
          for (final label in labels) {
            await tester.ensureVisible(find.text(label).first);
            await tester.pumpAndSettle();
            expectSafeLayout(tester);
            final text = tester.widget<Text>(find.text(label).first);
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(label),
                matching: find.byType(RichText),
              ),
            );
            for (var offset = 0; offset < label.length; offset++) {
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                expect(box.left, greaterThanOrEqualTo(0));
                // Selection bounds include subpixel trailing letter spacing.
                expect(
                  box.right,
                  lessThanOrEqualTo(paragraph.size.width + 0.1),
                );
                expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
              }
            }
          }
          expect(find.byType(Card), findsNothing);
        },
      );
    }
  }

  const expectedThrough2039 = [
    (2026, '10月時点', true),
    (2027, '10月時点の見込み', false),
    (2028, '10月時点の見込み', false),
    (2029, '10月時点の見込み', false),
    (2030, '10月時点の見込み', false),
    (2031, '10月時点の見込み', false),
    (2032, '10月時点の見込み', false),
    (2033, '10月時点の見込み', false),
    (2034, '10月時点の見込み', false),
    (2035, '10月時点の見込み', false),
    (2036, '10月時点の見込み', false),
    (2037, '10月時点の見込み', false),
    (2038, '10月時点の見込み', false),
    (2039, '10月時点の見込み', false),
  ];
  for (final scale in [1.0, 3.0]) {
    for (final testCase in const [
      (
        target: YearMonth(2040, 4),
        currentCount: 1,
        rows: [...expectedThrough2039, (2040, '4月時点の見込み', false)],
      ),
      (
        target: YearMonth(2026, 12),
        currentCount: 0,
        rows: [(2026, '12月時点の見込み', false)],
      ),
      (
        target: YearMonth(2026, 10),
        currentCount: 1,
        rows: [(2026, '10月時点', true)],
      ),
      (
        target: YearMonth(2025, 4),
        currentCount: 1,
        rows: [(2026, '10月時点', true)],
      ),
      (
        target: YearMonth(2026, 4),
        currentCount: 1,
        rows: [(2026, '10月時点', true)],
      ),
      (
        target: YearMonth(2040, 10),
        currentCount: 1,
        rows: [...expectedThrough2039, (2040, '10月時点の見込み', false)],
      ),
    ]) {
      testWidgets(
        'evaluation month and current marker for ${testCase.target} at scale $scale',
        (tester) async {
          const reference = YearMonth(2026, 10);
          final years = await pumpTimeline(
            tester,
            [],
            reference: reference,
            target: testCase.target,
            birth: const YearMonth(1970, 7),
            registration: const YearMonth(2018, 7),
            scale: scale,
          );
          expect(
            years.map((row) => row.year),
            orderedEquals(testCase.rows.map((expected) => expected.$1)),
          );
          for (final entry in years.indexed) {
            final row = entry.$2;
            final expected = testCase.rows[entry.$1];
            final year = expected.$1;
            final label = expected.$2;
            expect(inYear(year, label), findsOneWidget);
            expect(
              tester
                  .widgetList<Text>(
                    find.descendant(
                      of: yearSection(year),
                      matching: find.textContaining('月時点'),
                    ),
                  )
                  .map((text) => text.data),
              orderedEquals([label]),
            );
            expect(
              inYear(year, '現在'),
              expected.$3 ? findsOneWidget : findsNothing,
            );
            for (final value in [
              '${row.ownerAge}歳',
              '車齢${row.carAge}年',
              '約${formatKm(row.mileageKm)}',
            ]) {
              expect(inYear(year, value), findsOneWidget);
            }
            await tester.ensureVisible(inYear(year, label));
            await tester.pumpAndSettle();
            expectSafeLayout(tester);
            final text = tester.widget<Text>(inYear(year, label));
            expect(text.maxLines, isNull);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: inYear(year, label),
                matching: find.byType(RichText),
              ),
            );
            // Every character has laid-out glyph bounds within the paragraph.
            for (var offset = 0; offset < label.length; offset++) {
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                expect(box.left, greaterThanOrEqualTo(0));
                expect(box.right, lessThanOrEqualTo(paragraph.size.width));
                expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
              }
            }
          }
          // The engine's first-row flag retains its original meaning.
          expect(years.first.isCurrent, isTrue);
          expect(find.text('現在'), findsNWidgets(testCase.currentCount));
        },
      );
    }
  }

  testWidgets(
    'evaluation month does not truncate annual expenses or change classification',
    (tester) async {
      final input = [
        expense('目標後', 2040, 5, 900000),
        expense('12月', 2031, 12, 300),
        expense('同月先', 2031, 11, 100),
        expense('期限超過', 2026, 9, 800000),
        expense('同月後', 2031, 11, 200),
        expense('基準月', 2026, 10, 50),
        expense('目標月', 2040, 4, 400),
        expense('無料点検', 2032, 11, 0),
      ];
      final original = List<PlannedExpense>.of(input);
      final years = await pumpTimeline(
        tester,
        input,
        reference: const YearMonth(2026, 10),
        target: const YearMonth(2040, 4),
      );
      expect(inYear(2031, '10月時点の見込み'), findsOneWidget);
      expect(inYear(2031, '年間予定費 600円'), findsOneWidget);
      for (final row in years) {
        if (row.expenses.isEmpty) {
          expect(inYear(row.year, '予定費なし'), findsOneWidget);
        } else {
          expect(inYear(row.year, '予定費なし'), findsNothing);
          expect(
            inYear(row.year, '年間予定費 ${formatYen(row.totalYen)}'),
            findsOneWidget,
          );
          for (final expense in row.expenses) {
            expect(inYear(row.year, expense.name), findsOneWidget);
            expect(
              inYear(row.year, formatMonth(expense.plannedMonth)),
              findsWidgets,
            );
            expect(
              inYear(row.year, formatYen(expense.amountYen)),
              findsWidgets,
            );
          }
        }
      }
      final labels = ['同月先', '同月後', '12月'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i - 1])).dy,
          lessThan(tester.getTopLeft(find.text(labels[i])).dy),
        );
      }
      expect(find.text('期限超過'), findsNothing);
      expect(find.text('目標後'), findsNothing);
      expect(inYear(2032, '無料点検'), findsOneWidget);
      expect(inYear(2032, '年間予定費 0円'), findsOneWidget);
      expect(input, orderedEquals(original));
      expectSafeLayout(tester);
    },
  );

  testWidgets(
    'empty years through the supplied target keep all yearly values and only first current marker',
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
        (2035, '65歳', '車齢17年', '約84,666km'),
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

  testWidgets(
    'target year boundaries include January and final December only',
    (tester) async {
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
      expect(inYear(2035, '2035年12月'), findsNWidgets(2));
      expect(inYear(2035, '年間予定費 200円'), findsOneWidget);
    },
  );

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
        '約84,666km',
        name,
        '2035年12月',
        '3,000,000円',
        '年間予定費 3,000,000円',
      ]) {
        await tester.ensureVisible(find.text(label).last);
        await tester.pumpAndSettle();
        expectSafeLayout(tester);
        final widget = tester.widget<Text>(find.text(label).last);
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
        greaterThan(tester.getTopLeft(find.text('2035年12月').last).dy),
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
          testApp(
            session: session(
              initial: conditions(mileage: 12345, annual: 2000),
              birth: const YearMonth(1970, 4),
              reference: reference,
              registration: const YearMonth(2020, 4),
            ),
          ),
        );
        await tester.pumpAndSettle();
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
