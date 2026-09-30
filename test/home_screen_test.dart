import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'plan_test_support.dart';

void main() {
  testWidgets('Home is the current summary and four navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(find.text('70歳まで保有'), findsOneWidget);
    expect(find.text('65歳までに大型修理用として2,000,000円を備える'), findsOneWidget);
    for (final old in [
      'あと13年7か月',
      '今からの積立目安',
      '月30,000円',
      '約94,000円 / 月',
      '積立額の決め手',
      '約22年目',
      '約99,000km',
    ]) {
      expect(find.text(old), findsNothing);
    }
    expect(find.byType(Card), findsNothing);
    expect(find.byType(AppBar), findsNothing);
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets(
      'Home at 360px / $scale exposes all navigation without overflow',
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
            home: testApp(
              session: session(
                initial: conditions(
                  ownership: 100,
                  age: 100,
                  reserve: 1000000000,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          '100歳まで保有',
          '100歳までに大型修理用として1,000,000,000円を備える',
          '未来タイムラインを見る',
          '詳しく見る',
          '予定費を見る・追加する',
          '設定',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
        }
        for (final button in [
          find.widgetWithText(FilledButton, '予定費を見る・追加する'),
          find.widgetWithText(OutlinedButton, '設定'),
        ]) {
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
      },
    );
  }
}
