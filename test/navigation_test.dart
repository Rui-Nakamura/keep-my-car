import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';

void main() {
  const destinations = [
    ('未来タイムラインを見る', '未来タイムライン', ['70歳までの計画']),
    ('予定費を見る・追加する', '愛車予定費', ['6件の予定']),
    ('詳しく見る', '大型修理への備え', ['200万円', '65歳までに']),
    ('設定', '計画設定', ['愛車', 'オーナー', '保有目標', '現在の愛車資金', '普段の維持費', 'バックアップ']),
  ];

  for (final scale in [1.0, 3.0]) {
    for (final destination in destinations) {
      testWidgets(
        '${destination.$2}: navigation, skeleton and back at 360px / $scale',
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
              home: const KeepMyCarApp(),
            ),
          );
          final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
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
          expect(find.byType(TextField), findsNothing);
          expect(tester.takeException(), isNull);
          if (scale == 1.0) {
            await tester.tap(find.byType(BackButton));
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
          expect(
            tester.widget<HomeScreen>(find.byType(HomeScreen)),
            same(home),
          );
          expect(find.byType(AppBar), findsNothing);
          for (final label in ['70歳まで', 'あと13年7か月', '月30,000円']) {
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
