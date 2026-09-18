import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/theme/app_theme.dart';
import 'package:keep_my_car/domain/models/major_repair_reserve.dart';
import 'package:keep_my_car/domain/models/ownership_goal.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/features/repair_reserve/presentation/repair_reserve_screen.dart';

const explanation = '登録済みの予定費を支払いながら、65歳時点で大型修理用の資金を確保できるように計算しています。';
const disclaimer = '※大型修理の発生時期を予測するものではありません。';

Future<void> pumpReserve(
  WidgetTester tester, {
  double scale = 1,
  int fund = 0,
  int reserve = 60,
  YearMonth target = const YearMonth(2035, 4),
  List<PlannedExpense> expenses = const [],
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
      home: RepairReserveScreen(
        ownershipGoal: const OwnershipGoal(targetAge: 70),
        reserve: MajorRepairReserve(amountYen: reserve, targetAge: 65),
        result: calculateRepairReserve(
          referenceMonth: const YearMonth(2035, 2),
          currentCarFundYen: fund,
          reserveTargetMonth: target,
          largeRepairReserveYen: reserve,
          plannedExpenses: expenses,
        ),
      ),
    ),
  );
}

int _nextExpenseId = 1;

PlannedExpense expense(int amount) => PlannedExpense(
  id: _nextExpenseId++,
  name: '予定費',
  plannedMonth: const YearMonth(2035, 4),
  amountYen: amount,
  basis: ExpenseBasis.placeholder,
  memo: null,
  status: PlannedExpenseStatus.planned,
);

void expectSafeLayout(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    expect(widget.overflow, isNot(TextOverflow.ellipsis));
    expect(widget.maxLines, isNull);
  }
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  )) {
    expect(state.position.axis, Axis.vertical);
  }
  expect(find.byType(FittedBox), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('conditions, exact monthly results, and explanation in order', (
    tester,
  ) async {
    await pumpReserve(tester, expenses: [expense(90)]);
    const labels = [
      '保有目標',
      '70歳まで',
      '備え目標',
      '65歳まで',
      '想定大型修理',
      '60円',
      '必要な積立額',
      '予定費のみ',
      '月 30円',
      '大型修理込み',
      '月 50円',
      '大型修理への備え分',
      '＋20円／月',
      explanation,
      disclaimer,
    ];
    var previousY = double.negativeInfinity;
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      final y = tester.getTopLeft(find.text(label)).dy;
      expect(y, greaterThan(previousY));
      previousY = y;
    }
    final planned = tester.widget<Text>(find.text('月 30円')).style!;
    final included = tester.widget<Text>(find.text('月 50円')).style!;
    final additional = tester.widget<Text>(find.text('＋20円／月')).style!;
    expect(included.fontSize, greaterThan(additional.fontSize!));
    expect(additional.fontSize, greaterThan(planned.fontSize!));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('保存'), findsNothing);
    expectSafeLayout(tester);
  });

  testWidgets(
    'sufficient current funds display successful zero monthly amounts',
    (tester) async {
      await pumpReserve(tester, fund: 150, expenses: [expense(90)]);
      expect(find.text('月 0円'), findsNWidgets(2));
      expect(find.text('＋0円／月'), findsOneWidget);
      expect(find.text('計算できません'), findsNothing);
      expect(find.text(explanation), findsOneWidget);
    },
  );

  testWidgets('zero reserve remains a valid condition and result', (
    tester,
  ) async {
    await pumpReserve(tester, reserve: 0);
    expect(find.text('0円'), findsOneWidget);
    expect(find.text('月 0円'), findsNWidgets(2));
    expect(find.text('＋0円／月'), findsOneWidget);
    expect(find.text('計算できません'), findsNothing);
  });

  for (final pastTarget in [false, true]) {
    testWidgets(
      'invalid ${pastTarget ? 'target' : 'fund'} has no monthly result or placeholder',
      (tester) async {
        await pumpReserve(
          tester,
          fund: pastTarget ? 0 : -1,
          target: pastTarget
              ? const YearMonth(2035, 1)
              : const YearMonth(2035, 4),
          scale: 3,
        );
        expect(find.text('計算できません'), findsOneWidget);
        expect(
          find.text('計画データに確認が必要な項目があります。\n計画設定を見直してください。'),
          findsOneWidget,
        );
        for (final label in [
          '予定費のみ',
          '大型修理込み',
          '大型修理への備え分',
          '月 0円',
          '＋0円／月',
          '--円',
          explanation,
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.textContaining('月 '), findsNothing);
        expect(find.textContaining('／月'), findsNothing);
        await tester.ensureVisible(find.text(disclaimer));
        await tester.pumpAndSettle();
        expectSafeLayout(tester);
      },
    );
  }

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      '360px scale $scale shows large amounts and scrolls to full explanation',
      (tester) async {
        await pumpReserve(
          tester,
          scale: scale,
          reserve: 3000000,
          target: const YearMonth(2035, 2),
        );
        if (scale == 3) {
          expect(find.text(disclaimer).hitTestable(), findsNothing);
          expect(
            tester
                .state<ScrollableState>(find.byType(Scrollable))
                .position
                .maxScrollExtent,
            greaterThan(0),
          );
        }
        for (final label in [
          '3,000,000円',
          '月 3,000,000円',
          '＋3,000,000円／月',
          explanation,
          disclaimer,
        ]) {
          expect(find.text(label), findsOneWidget);
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expectSafeLayout(tester);
        }
        expect(find.text(disclaimer).hitTestable(), findsOneWidget);
        if (scale == 3) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(explanation),
              matching: find.byType(RichText),
            ),
          );
          final boxes = paragraph.getBoxesForSelection(
            const TextSelection(
              baseOffset: 0,
              extentOffset: explanation.length,
            ),
          );
          expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
        }
      },
    );
  }
}
