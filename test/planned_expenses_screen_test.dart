import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/theme/app_theme.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/planned_expenses/presentation/planned_expenses_screen.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import 'plan_test_support.dart';

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

Future<void> pumpExpenses(
  WidgetTester tester,
  List<PlannedExpense> expenses, {
  double scale = 1,
  double width = 360,
  YearMonth? reference,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final plan = session(expenses: expenses, reference: reference);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PlannedExpensesScreen(
        session: plan,
        onSaveExpense: plan.saveExpense,
        onDeleteExpense: plan.deleteExpense,
        onChanged: () {},
      ),
    ),
  );
}

void expectSafeLayout(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    expect(paragraph.didExceedMaxLines, isFalse);
    if (find
        .ancestor(
          of: find.byWidget(element.widget),
          matching: find.byType(AppBar),
        )
        .evaluate()
        .isEmpty) {
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

void main() {
  String summary(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('included-expenses-total')))
      .data!;

  testWidgets(
    'classification includes both boundaries and keeps outside rows below',
    (tester) async {
      final input = [
        expense('目標超過', 2040, 5, 900),
        expense('過去', 2026, 8, 800),
        expense('目標月', 2040, 4, 200),
        expense('基準月', 2026, 9, 100),
        expense('将来', 2027, 1, 300),
        expense('対象外無料', 2041, 1, 0),
      ];
      final original = List<PlannedExpense>.of(input);
      await pumpExpenses(tester, input);
      expect(summary(tester), '600円');
      expect(find.text('計画外の予定費：3件'), findsOneWidget);
      expect(find.text('合計 100円'), findsOneWidget);
      expect(find.text('合計 300円'), findsOneWidget);
      expect(find.text('合計 200円'), findsOneWidget);
      expect(find.text('合計 900円'), findsNothing);
      expect(find.text('予定年月が過ぎています'), findsOneWidget);
      expect(find.text('保有目標より先の予定です'), findsNWidgets(2));
      final names = ['基準月', '将来', '目標月', '過去', '目標超過', '対象外無料'];
      for (var i = 1; i < names.length; i++) {
        expect(
          tester.getTopLeft(find.text(names[i - 1])).dy,
          lessThan(tester.getTopLeft(find.text(names[i])).dy),
        );
      }
      for (final item in input) {
        final row = find.byKey(ValueKey('expense-${item.id}'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.text(
              '${item.plannedMonth.year}年${item.plannedMonth.month}月',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey('edit-expense-${item.id}')), findsOneWidget);
      }
      expect(input, orderedEquals(original));
      expectSafeLayout(tester);
    },
  );

  testWidgets(
    'past target: later-than-target reason wins even for overdue rows; CRUD remains available',
    (tester) async {
      await pumpExpenses(tester, [
        expense('両方', 2040, 5, 100),
        expense('目標と同月', 2040, 4, 200),
      ], reference: const YearMonth(2041, 1));
      expect(summary(tester), '0円');
      expect(find.text('計画外の予定費：2件'), findsOneWidget);
      expect(find.text('保有目標までの予定費はありません'), findsOneWidget);
      expect(find.text('計画内の予定費'), findsNothing);
      expect(find.text('保有目標より先の予定です'), findsOneWidget);
      expect(find.text('予定年月が過ぎています'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '予定費を追加'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '編集'), findsNWidgets(2));
    },
  );

  testWidgets('empty, outside-only and included zero are distinct', (
    tester,
  ) async {
    await pumpExpenses(tester, []);
    expect(summary(tester), '0円');
    expect(find.text('計画外の予定費：0件'), findsOneWidget);
    expect(find.text('予定費はまだありません'), findsOneWidget);
    expect(find.text('計画外の予定費'), findsNothing);
    await pumpExpenses(tester, [expense('過去無料', 2026, 8, 0)]);
    expect(summary(tester), '0円');
    expect(find.text('計画外の予定費：1件'), findsOneWidget);
    expect(find.text('保有目標までの予定費はありません'), findsOneWidget);
    expect(find.text('予定費はまだありません'), findsNothing);
    await pumpExpenses(tester, [expense('無料予定', 2026, 9, 0)]);
    expect(summary(tester), '0円');
    expect(find.text('無料予定'), findsOneWidget);
    expect(find.text('合計 0円'), findsOneWidget);
    expect(find.text('計画外の予定費：0件'), findsOneWidget);
    expect(find.text('保有目標までの予定費はありません'), findsNothing);
    expect(find.text('予定費はまだありません'), findsNothing);
  });

  testWidgets(
    'identical outside expenses retain distinct IDs and same-month original order',
    (tester) async {
      final input = [
        expense('後の月', 2042, 1, 50),
        expense('同じ対象外', 2041, 1, 10),
        expense('同月途中', 2041, 1, 20),
        expense('同じ対象外', 2041, 1, 10),
      ];
      await pumpExpenses(tester, input);
      expect(find.text('同じ対象外'), findsNWidgets(2));
      expect(find.text('計画外の予定費：4件'), findsOneWidget);
      final ordered = [input[1], input[2], input[3], input[0]];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          tester
              .getTopLeft(find.byKey(ValueKey('expense-${ordered[i - 1].id}')))
              .dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(ValueKey('expense-${ordered[i].id}')))
                .dy,
          ),
        );
      }
      for (final item in input) {
        expect(find.byKey(ValueKey('edit-expense-${item.id}')), findsOneWidget);
      }
    },
  );

  testWidgets(
    '320px scale 3: summary, full rows, reasons and edit are readable and reachable',
    (tester) async {
      final input = [
        expense('車' * 40, 2026, 9, 1000000000),
        expense('外' * 40, 2026, 8, 1000000000),
        expense('目標より先', 2040, 5, 0),
      ];
      await pumpExpenses(tester, input, width: 320, scale: 3);
      for (final finder in [
        find.byKey(const ValueKey('included-expenses-total')),
        find.text('計画外の予定費：2件'),
        find.text('合計 1,000,000,000円'),
        find.text('予定年月が過ぎています'),
        find.text('保有目標より先の予定です'),
        for (final item in input) ...[
          find.text(item.name),
          find.descendant(
            of: find.byKey(ValueKey('expense-${item.id}')),
            matching: find.text(
              '${item.plannedMonth.year}年${item.plannedMonth.month}月',
            ),
          ),
          find.descendant(
            of: find.byKey(ValueKey('expense-${item.id}')),
            matching: find.text(item.amountYen == 0 ? '0円' : '1,000,000,000円'),
          ),
          find.byKey(ValueKey('edit-expense-${item.id}')),
        ],
      ]) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder.hitTestable(), findsOneWidget);
        expectSafeLayout(tester);
      }
      await tester.tap(find.byKey(ValueKey('edit-expense-${input.last.id}')));
      await tester.pumpAndSettle();
      expect(find.text('予定費を編集'), findsWidgets);
    },
  );
  testWidgets(
    'Golden Sample: all six rows, year headers and totals via scroll',
    (tester) async {
      await pumpExpenses(tester, goldenSample.plannedExpenses);
      expect(find.text('6件の予定'), findsOneWidget);
      // Independent display expectations for the repository fixture.
      const amounts = [
        '80,000円',
        '220,000円',
        '800,000円',
        '500,000円',
        '700,000円',
        '250,000円',
      ];
      double previousY = -1;
      for (var i = 0; i < goldenSample.plannedExpenses.length; i++) {
        final item = goldenSample.plannedExpenses[i];
        final date = find.text(
          '${item.plannedMonth.year}年${item.plannedMonth.month}月',
        );
        final y = tester.getTopLeft(date).dy;
        expect(y, greaterThan(previousY));
        previousY = y;
      }
      for (var i = 0; i < goldenSample.plannedExpenses.length; i++) {
        final item = goldenSample.plannedExpenses[i];
        final date = find.text(
          '${item.plannedMonth.year}年${item.plannedMonth.month}月',
        );
        final row = find
            .ancestor(of: date, matching: find.byType(Column))
            .first;
        expect(
          find.descendant(of: row, matching: find.text(item.name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text(amounts[i])),
          findsOneWidget,
        );
        final header = find.text('${item.plannedMonth.year}年');
        expect(header, findsOneWidget);
        expect(find.text('合計 ${amounts[i]}'), findsOneWidget);
        expect(
          tester.getTopLeft(header).dy,
          lessThan(tester.getTopLeft(row).dy),
        );
        await tester.ensureVisible(date);
        await tester.pumpAndSettle();
        expect(date.hitTestable(), findsOneWidget);
        expectSafeLayout(tester);
      }
    },
  );

  testWidgets('sorts by month, preserves same-month input and original list', (
    tester,
  ) async {
    final input = [
      expense('翌年', 2028, 1, 10),
      expense('同月Z', 2027, 10, 300),
      expense('先月', 2027, 4, 20),
      expense('同月A', 2027, 10, 100),
      expense('同月M', 2027, 10, 200),
    ];
    final original = List<PlannedExpense>.of(input);
    await pumpExpenses(tester, input);
    final names = ['先月', '同月Z', '同月A', '同月M', '翌年'];
    for (var i = 1; i < names.length; i++) {
      expect(
        tester.getTopLeft(find.text(names[i - 1])).dy,
        lessThan(tester.getTopLeft(find.text(names[i])).dy),
      );
    }
    expect(input, orderedEquals(original));
    expectSafeLayout(tester);
  });

  testWidgets('combines multiple months per year and separates other years', (
    tester,
  ) async {
    await pumpExpenses(tester, [
      expense('翌年の予定', 2028, 6, 200000),
      expense('春の予定', 2027, 4, 100000),
      expense('秋の予定', 2027, 10, 50000),
    ]);
    expect(find.text('2027年'), findsOneWidget);
    expect(find.text('2028年'), findsOneWidget);
    expect(find.text('合計 150,000円'), findsOneWidget);
    expect(find.text('合計 200,000円'), findsOneWidget);
    final labels = ['2027年', '春の予定', '秋の予定', '2028年', '翌年の予定'];
    for (var i = 1; i < labels.length; i++) {
      expect(
        tester.getTopLeft(find.text(labels[i - 1])).dy,
        lessThan(tester.getTopLeft(find.text(labels[i])).dy),
      );
    }
    expectSafeLayout(tester);
  });

  testWidgets('empty list shows count and required fallback', (tester) async {
    await pumpExpenses(tester, []);
    expect(find.text('0件の予定'), findsOneWidget);
    expect(find.text('予定費はまだありません'), findsOneWidget);
    expectSafeLayout(tester);
  });

  testWidgets('identical expenses all remain visible and count toward total', (
    tester,
  ) async {
    await pumpExpenses(tester, [
      expense('同じ予定', 2027, 4, 100000),
      expense('同じ予定', 2027, 4, 100000),
    ]);
    expect(find.text('2件の予定'), findsOneWidget);
    expect(find.text('同じ予定'), findsNWidgets(2));
    expect(find.text('2027年4月'), findsNWidgets(2));
    expect(find.text('100,000円'), findsNWidgets(2));
    expect(find.text('合計 200,000円'), findsOneWidget);
    expectSafeLayout(tester);
  });

  testWidgets('30 expenses can be scrolled to the last row', (tester) async {
    await pumpExpenses(tester, [
      for (var i = 0; i < 30; i++)
        expense('予定${i + 1}', 2027 + i ~/ 12, i % 12 + 1, 1000),
    ]);
    expect(find.text('30件の予定'), findsOneWidget);
    expect(find.text('予定30').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(find.text('予定30'), 500);
    await tester.pumpAndSettle();
    expect(find.text('予定30').hitTestable(), findsOneWidget);
    expectSafeLayout(tester);
  });

  testWidgets('360px / scale 3 with long name, 3 million, year and total', (
    tester,
  ) async {
    const name = '長期間乗り続ける愛車のエンジンとトランスミッションの大規模整備予定';
    final item = expense(name, 2027, 4, 3000000);
    await pumpExpenses(tester, [item], scale: 3);
    final rowAmount = find.descendant(
      of: find.byKey(ValueKey('expense-${item.id}')),
      matching: find.text('3,000,000円'),
    );
    final total = find.byKey(const ValueKey('included-expenses-total'));
    expect(total, findsOneWidget);
    expect(tester.widget<Text>(total).data, '3,000,000円');
    await tester.ensureVisible(total);
    await tester.pumpAndSettle();
    expectSafeLayout(tester);
    final totalText = tester.widget<Text>(total);
    expect(totalText.maxLines, isNull);
    expect(totalText.overflow, isNot(TextOverflow.ellipsis));
    for (final label in [
      '2027年',
      '合計 3,000,000円',
      name,
      '2027年4月',
      '3,000,000円',
    ]) {
      final finder = label == '3,000,000円' ? rowAmount : find.text(label);
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expectSafeLayout(tester);
      final widget = tester.widget<Text>(finder);
      expect(widget.maxLines, isNull);
      expect(widget.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(find.byType(FittedBox), findsNothing);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(name), matching: find.byType(RichText)),
    );
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: name.length),
    );
    expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
    expect(
      tester.getTopLeft(rowAmount).dy,
      greaterThan(tester.getTopLeft(find.text('2027年4月')).dy),
    );
  });
}
