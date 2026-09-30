import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';

import 'plan_test_support.dart';

void main() {
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
      final link = find.text('詳しく見る');
      await tester.ensureVisible(link);
      await tester.tap(link);
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
        'これから10年間の計画',
        '2026年',
        '56歳',
        '車齢8年',
        '約45,000km',
        '12Vバッテリー',
        '2027年4月',
        '80,000円',
      ],
    ),
    ('予定費を見る・追加する', '愛車予定費', ['6件の予定']),
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

          final link = find.text(destination.$1);
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(find.byType(HomeScreen), findsNothing);
          expect(find.widgetWithText(AppBar, destination.$2), findsOneWidget);
          expect(find.byType(BackButton), findsOneWidget);
          for (final label in destination.$3) {
            expect(find.text(label), findsOneWidget);
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.text(label));
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
          for (final label in ['70歳まで保有', '65歳までに大型修理用として2,000,000円を備える']) {
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
