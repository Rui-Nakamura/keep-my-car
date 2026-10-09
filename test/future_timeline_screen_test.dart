import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
Finder timelineText(String label) {
  if (!label.startsWith('この年の予定費 ')) return find.text(label);
  // Compare the complete wording across the large-text label/amount newline.
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data ?? widget.textSpan!.toPlainText()).replaceAll('\n', ' ') ==
            label,
  );
}

Finder inYear(int year, String label) =>
    find.descendant(of: yearSection(year), matching: timelineText(label));

Future<List<TimelineYearData>> pumpTimeline(
  WidgetTester tester,
  List<PlannedExpense> expenses, {
  int age = 56,
  int targetAge = 70,
  double scale = 1,
  double width = 360,
  String? fontFamily,
  int year = 2026,
  YearMonth? reference,
  YearMonth? target,
  YearMonth? birth,
  YearMonth? registration,
}) async {
  tester.view.physicalSize = Size(width, 800);
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
      theme: fontFamily == null
          ? AppTheme.light
          : AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(fontFamily: fontFamily),
            ),
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
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    expect(state.position.axis, Axis.vertical);
  }
  expect(tester.takeException(), isNull);
}

RenderParagraph expectFullyLaidOut(
  WidgetTester tester,
  Finder finder,
  String label,
) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.text.toPlainText().replaceAll('\n', ' '), label);
  expect(paragraph.didExceedMaxLines, isFalse);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final scaler = MediaQuery.textScalerOf(tester.element(finder));
  for (var offset = 0; offset < label.length; offset++) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    expect(boxes, isNotEmpty, reason: '$label offset $offset');
    // A space consumed at a line break has no painted glyph.
    if (label[offset].trim().isEmpty) continue;
    final span = paragraph.text.getSpanForPosition(
      TextPosition(offset: offset),
    );
    final letterSpacing =
        span?.style?.letterSpacing ?? paragraph.text.style?.letterSpacing ?? 0;
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(0));
      expect(
        box.right,
        lessThanOrEqualTo(
          paragraph.size.width + scaler.scale(letterSpacing.abs()) + 0.1,
        ),
        reason: '$label offset $offset',
      );
      expect(
        paragraph.localToGlobal(Offset(box.right, box.top)).dx,
        lessThanOrEqualTo(width),
        reason: '$label offset $offset',
      );
      expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
    }
  }
  return paragraph;
}

void main() {
  setUpAll(() async {
    // Use Flutter's cached Android font for amount line-break tests, without
    // replacing the square test font used by the existing regression tests.
    final font = File.fromUri(
      Uri.file(Platform.resolvedExecutable)
          .resolve('../../material_fonts/roboto-regular.ttf'),
    );
    final loader = FontLoader('F2aRoboto')
      ..addFont(font.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  for (final amountCase in const [
    (width: 320.0, scale: 3.0, yen: 80000),
    (width: 320.0, scale: 3.0, yen: 100000),
    (width: 360.0, scale: 3.0, yen: 80000),
    (width: 360.0, scale: 3.0, yen: 100000),
    (width: 320.0, scale: 1.0, yen: 80000),
    (width: 360.0, scale: 1.0, yen: 100000),
    (width: 320.0, scale: 3.0, yen: 0),
    (width: 320.0, scale: 3.0, yen: 1000000000),
  ]) {
    testWidgets('F2a yearly amount ${amountCase.yen} at '
        '${amountCase.width}px scale ${amountCase.scale} uses readable lines', (
      tester,
    ) async {
      await pumpTimeline(
        tester,
        [expense('金額改行検証', 2026, 1, amountCase.yen)],
        width: amountCase.width,
        scale: amountCase.scale,
        fontFamily: 'F2aRoboto',
        target: const YearMonth(2026, 1),
      );
      final total = inYear(2026, 'この年の予定費 ${formatYen(amountCase.yen)}');
      await tester.ensureVisible(total);
      await tester.pumpAndSettle();
      final paragraph = expectFullyLaidOut(
        tester,
        total,
        'この年の予定費 ${formatYen(amountCase.yen)}',
      );
      final amount = formatYen(amountCase.yen);
      final start = paragraph.text.toPlainText().indexOf(amount);
      expect(start, greaterThanOrEqualTo(0));
      final amountStyle = paragraph.text
          .getSpanForPosition(TextPosition(offset: start))!
          .style!;
      expect(amountStyle.fontSize, greaterThanOrEqualTo(16));
      expect(amountStyle.fontSize, lessThanOrEqualTo(28));
      if (amountCase.scale == 1) {
        expect(amountStyle.fontSize, 28);
      }
      expect(
        paragraph.textScaler.scale(amountStyle.fontSize!),
        amountStyle.fontSize! * amountCase.scale,
      );
      final lines = <double, String>{};
      for (var index = 0; index < amount.length; index++) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start + index,
            extentOffset: start + index + 1,
          ),
        );
        expect(boxes, hasLength(1));
        final top = (boxes.single.top * 1000).round() / 1000;
        lines.update(
          top,
          (line) => '$line${amount[index]}',
          ifAbsent: () => amount[index],
        );
      }
      debugPrint(
        'F2a amount layout: ${amountCase.width}px / ${amountCase.scale}, '
        '$amount, available=${paragraph.size.width}, '
        'baseSize=${amountStyle.fontSize}, lines=${lines.values.toList()}',
      );
      if (amountCase.yen != 1000000000) {
        expect(lines.values.toList(), [
          amount,
        ], reason: 'The actual painted amount must stay on one line.');
      }
      if (amountCase.yen == 1000000000) {
        expect(amountStyle.fontSize, 16);
        expect(lines.length, greaterThan(1));
        expect(lines.values.join(), amount);
      }
      final semantics = tester.widget<Semantics>(
        find.ancestor(of: total, matching: find.byType(Semantics)).first,
      );
      expect(semantics.properties.label, 'この年の予定費、$amount');
      expect(inYear(2026, '金額改行検証'), findsOneWidget);
      expect(inYear(2026, amount), findsOneWidget);
      expectSafeLayout(tester);
    });
  }

  for (final amountCase in const [
    (width: 320.0, yen: 1000000),
    (width: 360.0, yen: 1000000),
    (width: 320.0, yen: 10000000),
    (width: 360.0, yen: 10000000),
  ]) {
    testWidgets('F2a high yearly amount ${amountCase.yen} at '
        '${amountCase.width}px scale 3.0 preserves every painted character', (
      tester,
    ) async {
      await pumpTimeline(
        tester,
        [expense('高額表示検証', 2026, 1, amountCase.yen)],
        width: amountCase.width,
        scale: 3,
        fontFamily: 'F2aRoboto',
        target: const YearMonth(2026, 1),
      );
      final amount = formatYen(amountCase.yen);
      final total = inYear(2026, 'この年の予定費 $amount');
      await tester.ensureVisible(total);
      await tester.pumpAndSettle();
      final paragraph = expectFullyLaidOut(tester, total, 'この年の予定費 $amount');
      final start = paragraph.text.toPlainText().indexOf(amount);
      expect(start, greaterThanOrEqualTo(0));
      final lines = <double, String>{};
      for (var index = 0; index < amount.length; index++) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start + index,
            extentOffset: start + index + 1,
          ),
        );
        expect(boxes, hasLength(1), reason: '$amount character $index');
        expect(boxes.single.right - boxes.single.left, greaterThan(0));
        expect(boxes.single.bottom - boxes.single.top, greaterThan(0));
        final top = (boxes.single.top * 1000).round() / 1000;
        lines.update(
          top,
          (line) => '$line${amount[index]}',
          ifAbsent: () => amount[index],
        );
      }
      expect(lines.values.join(), amount);
      expectSafeLayout(tester);
      debugPrint(
        'F2a high amount layout: ${amountCase.width}px / 3.0, '
        '$amount, available=${paragraph.size.width}, '
        'lines=${lines.values.toList()}',
      );
    });
  }

  testWidgets('F1 cards, nodes and goal expose the roadmap hierarchy', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      [expense('目標年の整備', 2028, 4, 800000)],
      target: const YearMonth(2028, 4),
      targetAge: 58,
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor!.computeLuminance(), lessThan(0.1));
    final nodePaints = <(Color?, Color)>{};
    for (final year in [2026, 2027, 2028]) {
      final card = tester.widget<Container>(
        find.byKey(ValueKey('timeline-card-$year')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.gradient!.colors.length, greaterThanOrEqualTo(2));
      expect(decoration.borderRadius, isNotNull);
      expect((decoration.border! as Border).top.width, greaterThan(0));
      final dot = tester.widget<Container>(
        find.byKey(ValueKey('timeline-dot-$year')),
      );
      final node = dot.decoration! as BoxDecoration;
      expect(node.shape, BoxShape.circle);
      final border = node.border! as Border;
      expect(border.top.width, greaterThanOrEqualTo(2));
      nodePaints.add((node.color, border.top.color));
      expect(
        tester.getRect(find.byKey(ValueKey('timeline-dot-$year'))).center.dy,
        closeTo(tester.getRect(inYear(year, '$year年')).center.dy, 0.1),
      );
    }
    // Current, ordinary and goal years must not share the same node paint.
    expect(nodePaints.length, 3);
    final target = find.byKey(const ValueKey('timeline-target-2028'));
    expect(target, findsOneWidget);
    for (final label in ['保有目標', '2028年4月', '58歳まで乗る計画']) {
      expect(
        find.descendant(of: target, matching: find.text(label)),
        findsOneWidget,
      );
    }
    final flag = tester.widget<Icon>(
      find.descendant(of: target, matching: find.byIcon(Icons.flag_outlined)),
    );
    expect(flag.size, greaterThanOrEqualTo(28));
    final total = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-total-2028')),
        matching: find.byType(Text),
      ),
    );
    expect(total.textSpan!.toPlainText(), 'この年の予定費 800,000円');
    final amount = total.textSpan!.getSpanForPosition(
      const TextPosition(offset: 'この年の予定費 '.length),
    );
    final label = total.textSpan!.getSpanForPosition(
      const TextPosition(offset: 0),
    );
    expect(amount!.style!.fontSize, greaterThan(label!.style!.fontSize!));
    expect(
      amount.style!.fontWeight!.value,
      greaterThan(label.style!.fontWeight!.value),
    );
    expect(inYear(2028, '目標年の整備'), findsOneWidget);
    expectSafeLayout(tester);
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      'F1 320px scale $scale keeps goal data, zero entries and long details',
      (tester) async {
        const name = 'フロント・リアブレーキディスクおよびパッド一式交換と関連部品点検・交換整備';
        final input = [
          expense('無料点検', 2027, 12, 0),
          expense(name, 2028, 4, 1000000000),
          expense('目標月の無料診断', 2028, 4, 0),
        ];
        final original = List<PlannedExpense>.of(input);
        var rows = await pumpTimeline(
          tester,
          input,
          width: 320,
          target: const YearMonth(2028, 4),
          targetAge: 58,
        );
        final normalHeights = {
          for (final row in rows)
            row.year: tester.getSize(yearSection(row.year)).height,
        };
        if (scale == 3) {
          rows = await pumpTimeline(
            tester,
            input,
            width: 320,
            scale: scale,
            target: const YearMonth(2028, 4),
            targetAge: 58,
          );
          for (final row in rows) {
            expect(
              tester.getSize(yearSection(row.year)).height,
              greaterThan(normalHeights[row.year]!),
            );
            expect(
              tester.getTopLeft(inYear(row.year, '車齢 ${row.carAge}年')).dy,
              greaterThan(
                tester.getTopLeft(inYear(row.year, 'オーナー ${row.ownerAge}歳')).dy,
              ),
            );
          }
        }
        expect(rows.map((row) => row.year), orderedEquals([2026, 2027, 2028]));
        expect(
          rows.map((row) => row.totalYen),
          orderedEquals([0, 0, 1000000000]),
        );
        expect(inYear(2026, '予定費の登録はありません'), findsOneWidget);
        expect(inYear(2027, '予定費の登録はありません'), findsNothing);
        expect(inYear(2028, '予定費の登録はありません'), findsNothing);
        expect(find.text(name), findsOneWidget);
        expect(find.text('目標月の無料診断'), findsOneWidget);
        expectFullyLaidOut(tester, find.text('未来タイムライン'), '未来タイムライン');
        for (final row in rows) {
          final dot = tester.getRect(
            find.byKey(ValueKey('timeline-dot-${row.year}')),
          );
          final heading = tester.getRect(inYear(row.year, '${row.year}年'));
          expect(dot.center.dy, greaterThanOrEqualTo(heading.top));
          expect(dot.center.dy, lessThanOrEqualTo(heading.bottom));
          final labels = [
            '${row.year}年',
            row.year == 2026
                ? '1月時点'
                : row.year == 2028
                ? '4月時点の見込み'
                : '1月時点の見込み',
            'オーナー ${row.ownerAge}歳',
            '車齢 ${row.carAge}年',
            '想定走行距離 約${formatKm(row.mileageKm)}',
            'この年の予定費 ${formatYen(row.totalYen)}',
            if (row.year == 2026) '現在',
            if (row.expenses.isEmpty) '予定費の登録はありません',
            if (row.year == 2028) ...['保有目標', '2028年4月', '58歳まで乗る計画'],
            for (final item in row.expenses) item.name,
          ];
          for (final label in labels) {
            final finder = inYear(row.year, label);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            final paragraph = expectFullyLaidOut(tester, finder, label);
            final bounds =
                paragraph.localToGlobal(Offset.zero) & paragraph.size;
            final rowBounds = tester.getRect(yearSection(row.year));
            expect(bounds.top, greaterThanOrEqualTo(rowBounds.top));
            expect(bounds.bottom, lessThanOrEqualTo(rowBounds.bottom));
            expectSafeLayout(tester);
          }
          for (final item in row.expenses) {
            final group = find
                .ancestor(
                  of: inYear(row.year, item.name),
                  matching: find.byType(Semantics),
                )
                .first;
            for (final label in [
              '${item.plannedMonth.month}月',
              formatYen(item.amountYen),
            ]) {
              final finder = find.descendant(
                of: group,
                matching: find.text(label),
              );
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              expectFullyLaidOut(tester, finder, label);
              expectSafeLayout(tester);
            }
          }
        }
        final paragraph = expectFullyLaidOut(tester, find.text(name), name);
        final boxes = paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: name.length),
        );
        expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
        expect(
          find.byKey(const ValueKey('timeline-line-out-2028')),
          findsNothing,
        );
        await tester.ensureVisible(inYear(2028, '2028年4月'));
        await tester.pumpAndSettle();
        expect(inYear(2028, '2028年4月').hitTestable(), findsOneWidget);
        expect(input, orderedEquals(original));
        expect(find.byType(FittedBox), findsNothing);
        expectSafeLayout(tester);
      },
    );
  }

  for (final target in [const YearMonth(2026, 10), const YearMonth(2025, 4)]) {
    testWidgets('F1 320px scale 3 retains target state and speech at $target', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpTimeline(
          tester,
          [expense('保有期間外の保存済み予定費', 2029, 1, 100)],
          reference: const YearMonth(2026, 10),
          target: target,
          targetAge: 55,
          width: 320,
          scale: 3,
        );
        final current = target == const YearMonth(2026, 10);
        final labels = current
            ? ['今月が保有目標です', '保有目標：2026年10月', '55歳まで乗る計画']
            : [
                '保有目標に到達しています',
                '設定している保有目標：55歳・2025年4月',
                '登録済みの予定費は削除されていません。「愛車予定費」から確認できます。',
              ];
        for (final label in labels) {
          final finder = find.text(label);
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expectFullyLaidOut(tester, finder, label);
          expectSafeLayout(tester);
        }
        final label = current
            ? '保有目標、2026年10月、55歳まで乗る計画'
            : '保有目標に到達しています。設定している保有目標、55歳、2025年4月';
        final semantics = find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        );
        await tester.ensureVisible(semantics);
        await tester.pumpAndSettle();
        final node = tester.getSemantics(semantics);
        expect(node.getSemanticsData().label, label);
        expect(
          node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder),
          isEmpty,
        );
        expect(
          find.byIcon(Icons.flag_outlined),
          current ? findsOneWidget : findsNothing,
        );
        if (!current) {
          expect(
            find.byKey(const ValueKey('timeline-target-2026')),
            findsNothing,
          );
          expect(find.text('55歳まで乗る計画'), findsNothing);
        }
        expect(inYear(2026, '現在'), findsOneWidget);
        expect(inYear(2026, 'オーナー 56歳'), findsOneWidget);
        expect(inYear(2026, '車齢 8年'), findsOneWidget);
        expect(inYear(2026, '10月時点'), findsOneWidget);
        expect(inYear(2026, 'この年の予定費 0円'), findsOneWidget);
        expect(yearSection(2027), findsNothing);
        expectSafeLayout(tester);
      } finally {
        handle.dispose();
      }
    });
  }

  for (final scale in [1.0, 3.0]) {
    testWidgets('D1c connected dots stop at final year, scale $scale', (
      tester,
    ) async {
      await pumpTimeline(
        tester,
        [],
        target: const YearMonth(2028, 4),
        scale: scale,
      );
      final firstDot = tester.getRect(
        find.byKey(const ValueKey('timeline-dot-2026')),
      );
      for (final year in [2026, 2027]) {
        final line = tester.getRect(
          find.byKey(ValueKey('timeline-line-out-$year')),
        );
        final dot = tester.getRect(find.byKey(ValueKey('timeline-dot-$year')));
        final nextLine = tester.getRect(
          find.byKey(ValueKey('timeline-line-in-${year + 1}')),
        );
        final nextDot = tester.getRect(
          find.byKey(ValueKey('timeline-dot-${year + 1}')),
        );
        expect(line.width, greaterThanOrEqualTo(2));
        expect(nextLine.width, line.width);
        expect(line.top, dot.center.dy);
        expect(line.bottom, nextLine.top);
        expect(nextLine.bottom, nextDot.center.dy);
        expect(line.center.dx, firstDot.center.dx);
      }
      expect(find.byKey(const ValueKey('timeline-line-in-2026')), findsNothing);
      expect(
        find.byKey(const ValueKey('timeline-line-out-2028')),
        findsNothing,
      );
      for (final year in [2026, 2027, 2028]) {
        final dot = tester.getRect(find.byKey(ValueKey('timeline-dot-$year')));
        expect(dot.width, greaterThanOrEqualTo(16));
        expect(dot.height, dot.width);
        expect(dot.center.dx, firstDot.center.dx);
        for (final element
            in find
                .descendant(
                  of: find.byKey(ValueKey('timeline-card-$year')),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.localToGlobal(Offset.zero).dx,
            greaterThan(dot.right),
          );
        }
      }
      expectSafeLayout(tester);
      await pumpTimeline(
        tester,
        [],
        target: const YearMonth(2026, 1),
        scale: scale,
      );
      expect(find.byKey(const ValueKey('timeline-dot-2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline-line-in-2026')), findsNothing);
      expect(
        find.byKey(const ValueKey('timeline-line-out-2026')),
        findsNothing,
      );
      expect(yearSection(2027), findsNothing);
      expectSafeLayout(tester);
    });

    testWidgets(
      'D1c fixed boundary totals, all two-stage details and reading order, scale $scale',
      (tester) async {
        final input = [
          expense('目標後', 2027, 5, 900000),
          expense('11月後', 2026, 11, 200),
          expense('基準月前', 2026, 9, 800000),
          expense('基準月', 2026, 10, 50),
          expense('11月先', 2026, 11, 100),
          expense('目標月', 2027, 4, 400),
        ];
        final original = List<PlannedExpense>.of(input);
        final rows = await pumpTimeline(
          tester,
          input,
          reference: const YearMonth(2026, 10),
          target: const YearMonth(2027, 4),
          scale: scale,
        );
        expect(rows.map((row) => row.totalYen), orderedEquals([350, 400]));
        expect(
          rows.first.expenses.map((item) => item.name),
          orderedEquals(['基準月', '11月後', '11月先']),
        );
        expect(inYear(2026, '10月時点'), findsOneWidget);
        expect(inYear(2026, 'この年の予定費 350円'), findsOneWidget);
        expect(inYear(2027, 'この年の予定費 400円'), findsOneWidget);
        expect(find.text('目標後'), findsNothing);
        expect(find.text('基準月前'), findsNothing);
        expect(input, orderedEquals(original));
        for (final detail in [
          (2026, '基準月', '10月', '50円'),
          (2026, '11月後', '11月', '200円'),
          (2026, '11月先', '11月', '100円'),
          (2027, '目標月', '4月', '400円'),
        ]) {
          final name = inYear(detail.$1, detail.$2);
          final group = find
              .ancestor(of: name, matching: find.byType(Semantics))
              .first;
          final month = find.descendant(
            of: group,
            matching: find.text(detail.$3),
          );
          final amount = find.descendant(
            of: group,
            matching: find.text(detail.$4),
          );
          expect(month, findsOneWidget);
          expect(amount, findsOneWidget);
          expect(
            tester.getTopLeft(month).dy,
            lessThan(tester.getTopLeft(name).dy),
          );
          expect(
            tester.getTopLeft(amount).dy,
            greaterThanOrEqualTo(tester.getTopLeft(name).dy),
          );
          expect(
            tester
                .getBottomLeft(
                  inYear(
                    detail.$1,
                    detail.$1 == 2026 ? 'この年の予定費 350円' : 'この年の予定費 400円',
                  ),
                )
                .dy,
            lessThan(tester.getTopLeft(month).dy),
          );
        }
        final ordered = [
          '2026年',
          '10月時点',
          'オーナー 56歳',
          '想定走行距離 約45,000km',
          'この年の予定費 350円',
          '基準月',
          '11月後',
          '11月先',
        ];
        for (var i = 1; i < ordered.length; i++) {
          expect(
            tester.getTopLeft(inYear(2026, ordered[i])).dy,
            greaterThan(tester.getTopLeft(inYear(2026, ordered[i - 1])).dy),
          );
        }
        expectSafeLayout(tester);
        expect(find.textContaining('予想走行距離'), findsNothing);
      },
    );
  }

  testWidgets('D1c semantics link values without duplicate child speech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTimeline(
      tester,
      [expense('ブレーキ整備', 2026, 11, 800000), expense('予防点検', 2026, 12, 0)],
      reference: const YearMonth(2026, 10),
      target: const YearMonth(2027, 4),
    );
    for (final label in [
      '2026年、10月時点、現在',
      'オーナー56歳、車齢8年、想定走行距離、約45,000キロメートル',
      'この年の予定費、800,000円',
      '11月、ブレーキ整備、800,000円',
      '12月、予防点検、0円',
      '2027年、4月時点の見込み',
      '保有目標、2027年4月、70歳まで乗る計画',
    ]) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(finder);
      expect(node.getSemanticsData().label, label);
      expect(
        node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder),
        isEmpty,
      );
      final widget = tester.widget<Semantics>(finder);
      expect(widget.excludeSemantics, isTrue);
      expect(widget.properties.liveRegion, isNot(true));
    }
    expect(find.textContaining('所有者'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('所有者')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('予想走行距離')), findsNothing);
    handle.dispose();
  });

  for (final target in [
    const YearMonth(2026, 10),
    const YearMonth(2026, 4),
    const YearMonth(2025, 4),
  ]) {
    testWidgets('D1c target semantics for $target', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTimeline(
        tester,
        [],
        reference: const YearMonth(2026, 10),
        target: target,
        targetAge: 55,
      );
      final label = target == const YearMonth(2026, 10)
          ? '保有目標、2026年10月、55歳まで乗る計画'
          : target == const YearMonth(2026, 4)
          ? '保有目標に到達しています。設定している保有目標、55歳、2026年4月'
          : '保有目標に到達しています。設定している保有目標、55歳、2025年4月';
      final finder = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(finder).getSemanticsData().label, label);
      if (target == const YearMonth(2026, 10)) {
        await tester.ensureVisible(find.text('今月が保有目標です'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('今月が保有目標です'), findsOneWidget);
      }
      handle.dispose();
    });
  }

  testWidgets('D1c renders supplied yearly total rather than summing details', (
    tester,
  ) async {
    // Deliberately distinct fixture values prove that presentation uses totalYen.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FutureTimelineScreen(
          years: [
            TimelineYearData(
              year: 2026,
              ownerAge: 56,
              carAge: 8,
              mileageKm: 45000,
              isCurrent: true,
              expenses: [expense('渡された明細', 2026, 10, 100)],
              totalYen: 950000,
            ),
          ],
          referenceMonth: const YearMonth(2026, 10),
          ownershipTargetMonth: const YearMonth(2026, 10),
          ownershipTargetAge: 56,
          ownershipTargetReached: false,
          hasSavedPlannedExpenses: true,
        ),
      ),
    );
    expect(find.text('この年の予定費 950,000円'), findsOneWidget);
    expect(find.text('100円'), findsOneWidget);
    expect(find.text('この年の予定費 100円'), findsNothing);
  });

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
          expect(
            find.byKey(ValueKey('timeline-card-${targetCase.last}')),
            findsOneWidget,
          );
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
              'オーナー ${row.ownerAge}歳',
              '車齢 ${row.carAge}年',
              '想定走行距離 約${formatKm(row.mileageKm)}',
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
        expense('12月整備', 2031, 12, 300),
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
      expect(inYear(2031, 'この年の予定費 600円'), findsOneWidget);
      for (final row in years) {
        if (row.expenses.isEmpty) {
          expect(inYear(row.year, '予定費の登録はありません'), findsOneWidget);
        } else {
          expect(inYear(row.year, '予定費の登録はありません'), findsNothing);
          expect(
            inYear(row.year, 'この年の予定費 ${formatYen(row.totalYen)}'),
            findsOneWidget,
          );
          for (final expense in row.expenses) {
            expect(inYear(row.year, expense.name), findsOneWidget);
            expect(
              inYear(row.year, '${expense.plannedMonth.month}月'),
              findsWidgets,
            );
            expect(
              inYear(row.year, formatYen(expense.amountYen)),
              findsWidgets,
            );
          }
        }
      }
      final labels = ['同月先', '同月後', '12月整備'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i - 1])).dy,
          lessThan(tester.getTopLeft(find.text(labels[i])).dy),
        );
      }
      expect(find.text('期限超過'), findsNothing);
      expect(find.text('目標後'), findsNothing);
      expect(inYear(2032, '無料点検'), findsOneWidget);
      expect(inYear(2032, 'この年の予定費 0円'), findsOneWidget);
      expect(input, orderedEquals(original));
      expectSafeLayout(tester);
    },
  );

  testWidgets(
    'empty years through the supplied target keep all yearly values and only first current marker',
    (tester) async {
      await pumpTimeline(tester, []);
      const expected = [
        (2026, 'オーナー 56歳', '車齢 8年', '想定走行距離 約45,000km'),
        (2027, 'オーナー 57歳', '車齢 9年', '想定走行距離 約49,000km'),
        (2028, 'オーナー 58歳', '車齢 10年', '想定走行距離 約53,000km'),
        (2029, 'オーナー 59歳', '車齢 11年', '想定走行距離 約57,000km'),
        (2030, 'オーナー 60歳', '車齢 12年', '想定走行距離 約61,000km'),
        (2031, 'オーナー 61歳', '車齢 13年', '想定走行距離 約65,000km'),
        (2032, 'オーナー 62歳', '車齢 14年', '想定走行距離 約69,000km'),
        (2033, 'オーナー 63歳', '車齢 15年', '想定走行距離 約73,000km'),
        (2034, 'オーナー 64歳', '車齢 16年', '想定走行距離 約77,000km'),
        (2035, 'オーナー 65歳', '車齢 17年', '想定走行距離 約84,666km'),
      ];
      double previousY = -1;
      for (final row in expected) {
        for (final label in [
          '${row.$1}年',
          row.$2,
          row.$3,
          row.$4,
          '予定費の登録はありません',
        ]) {
          expect(inYear(row.$1, label), findsOneWidget);
        }
        final y = tester.getTopLeft(yearSection(row.$1)).dy;
        expect(y, greaterThan(previousY));
        previousY = y;
      }
      expect(find.text('予定費の登録はありません'), findsNWidgets(10));
      expect(find.text('この年の予定費 0円'), findsNWidgets(10));
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
      final before = tester.widget<Text>(inYear(2026, 'オーナー $age歳')).style!;
      final milestone = tester
          .widget<Text>(inYear(2027, 'オーナー ${age + 1}歳'))
          .style!;
      final after = tester
          .widget<Text>(inYear(2028, 'オーナー ${age + 2}歳'))
          .style!;
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
      for (final label in ['春', '同月Z', '同月A', '4月', 'この年の予定費 150,000円']) {
        expect(inYear(2027, label), findsOneWidget);
      }
      expect(inYear(2027, '10月'), findsNWidgets(2));
      expect(inYear(2028, '翌年'), findsOneWidget);
      expect(inYear(2028, 'この年の予定費 200,000円'), findsOneWidget);
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
      expect(inYear(2026, '予定費の登録はありません'), findsOneWidget);
      expect(
        find.descendant(
          of: yearSection(2026),
          matching: find.text('この年の予定費 0円'),
        ),
        findsOneWidget,
      );
      expect(inYear(2027, '無料点検'), findsOneWidget);
      expect(inYear(2027, 'この年の予定費 0円'), findsOneWidget);
      for (final label in [
        '12V点検',
        'タイヤ交換',
        '0円',
        '100,000円',
        'この年の予定費 100,000円',
      ]) {
        expect(inYear(2028, label), findsOneWidget);
      }
      for (final label in ['無料診断A', '無料診断B', 'この年の予定費 0円']) {
        expect(inYear(2029, label), findsOneWidget);
      }
      expect(inYear(2029, '0円'), findsNWidgets(2));
      for (final year in [2027, 2028, 2029]) {
        expect(inYear(year, '予定費の登録はありません'), findsNothing);
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
      expect(inYear(2026, '1月'), findsOneWidget);
      expect(inYear(2026, 'この年の予定費 100円'), findsOneWidget);
      expect(inYear(2035, '最後'), findsOneWidget);
      expect(inYear(2035, '12月'), findsOneWidget);
      expect(inYear(2035, 'この年の予定費 200円'), findsOneWidget);
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
        'オーナー 65歳',
        '車齢 17年',
        '想定走行距離 約84,666km',
        name,
        '2035年12月',
        '12月',
        '3,000,000円',
        'この年の予定費 3,000,000円',
      ]) {
        await tester.ensureVisible(timelineText(label).last);
        await tester.pumpAndSettle();
        expectSafeLayout(tester);
        final widget = tester.widget<Text>(timelineText(label).last);
        expect(widget.maxLines, isNull);
        expect(widget.overflow, isNot(TextOverflow.ellipsis));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: timelineText(label).last,
            matching: find.byType(RichText),
          ),
        );
        for (var offset = 0; offset < label.length; offset++) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          );
          expect(boxes, isNotEmpty);
          // A space consumed at a line break has no visible glyph and its
          // selection rectangle may extend beyond the line's painted text.
          if (label[offset].trim().isEmpty) continue;
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(0));
            // Selection includes scaled trailing letter spacing; glyphs must
            // still stay inside the screen, with no omitted characters.
            final trailingSpacing =
                (widget.style?.letterSpacing ?? 0).abs() * 3;
            expect(
              box.right,
              lessThanOrEqualTo(paragraph.size.width + trailingSpacing + 0.1),
              reason: "$label offset $offset",
            );
            expect(
              paragraph.localToGlobal(Offset(box.right, box.top)).dx,
              lessThanOrEqualTo(360),
            );
            expect(box.bottom, lessThanOrEqualTo(paragraph.size.height));
          }
        }
      }
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(name), matching: find.byType(RichText)),
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: name.length),
      );
      expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
      expect(find.byType(FittedBox), findsNothing);
      expect(find.byKey(const ValueKey('timeline-card-2035')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('3,000,000円')).dy,
        greaterThan(tester.getTopLeft(find.text('12月')).dy),
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
          inYear(2030, reference.month == 3 ? 'オーナー 59歳' : 'オーナー 60歳'),
          findsOneWidget,
        );
        expect(
          inYear(2030, reference.month == 3 ? '車齢 9年' : '車齢 10年'),
          findsOneWidget,
        );
        expect(inYear(2030, '想定走行距離 約12,345km'), findsOneWidget);
        expect(inYear(2031, '想定走行距離 約14,345km'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
