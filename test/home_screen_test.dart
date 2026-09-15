import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';

void main() {
  const content = [
    '70歳まで',
    'あと13年7か月',
    '月30,000円',
    '約94,000円 / 月',
    '約64,000円',
    '30,000円',
    '2035年4月',
    '約22年目',
    '約99,000km',
    '200万円',
    '65歳までに',
    '2027年4月',
    '12Vバッテリー',
    '80,000円',
    '6件の予定',
  ];

  testWidgets('Home displays the approved normal sample', (tester) async {
    await tester.pumpWidget(const KeepMyCarApp());
    for (final label in content) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('タイヤ'), findsNothing);
    expect(find.text('2,550,000円'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets('360px width at text scale $scale scrolls without overflow', (
      tester,
    ) async {
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
      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      expect(scrollable.position.axis, Axis.vertical);
      if (scale == 1) {
        for (final label in ['70歳まで', 'あと13年7か月', '今からの積立目安', '月30,000円']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(800));
        }
      }
      for (final label in [
        ...content,
        '未来タイムラインを見る',
        '詳しく見る',
        '予定費を見る・追加する',
        '設定',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(360), reason: label);
      }
      expect(scrollable.position.pixels, greaterThan(0));
    });
  }

  testWidgets('Add expense and settings are accessible navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(const KeepMyCarApp());
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    final button = find.widgetWithText(FilledButton, '予定費を見る・追加する');
    await tester.ensureVisible(button);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '愛車予定費'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final settings = find.ancestor(
      of: find.text('設定'),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(settings);
    expect(tester.getSize(settings).height, greaterThanOrEqualTo(48));
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '計画設定'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)), same(home));
    expect(tester.takeException(), isNull);
  });
}
