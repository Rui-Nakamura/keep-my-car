import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/domain/plan_conditions_validation.dart';

import 'plan_test_support.dart';

Finder input(String field) => find.byKey(ValueKey('input-$field'));
Future<void> openSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('設定'));
  await tester.tap(find.text('設定'));
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String field, String value) async {
  await tester.ensureVisible(input(field));
  await tester.enterText(input(field), value);
  await tester.pump();
}

Future<void> apply(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('apply-plan')));
  await tester.tap(find.byKey(const ValueKey('apply-plan')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'draft is separate, Back discards, valid six-field set returns Home',
    (tester) async {
      final plan = session();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await enter(tester, 'annualMileage', '6000');
      expect(plan.conditions.annualMileageKm, 4000);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(plan.conditions.annualMileageKm, 4000);
      await openSettings(tester);
      expect(
        tester.widget<TextField>(input('annualMileage')).controller!.text,
        '4,000',
      );
      await enter(tester, 'currentMileage', '50000');
      await enter(tester, 'annualMileage', '6000');
      await tester.ensureVisible(input('ownershipAge'));
      await tester.tap(input('ownershipAge'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('age-option-80')));
      await tester.tap(find.byKey(const ValueKey('age-option-80')));
      await tester.pumpAndSettle();
      await enter(tester, 'fund', '1000000');
      await tester.ensureVisible(input('reserveAge'));
      await tester.tap(input('reserveAge'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('age-option-56')), findsNothing);
      expect(find.byKey(const ValueKey('age-option-57')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('age-option-66')));
      await tester.tap(find.byKey(const ValueKey('age-option-66')));
      await tester.pumpAndSettle();
      await enter(tester, 'reserve', '3000000');
      await apply(tester);
      expect(
        plan.conditions,
        conditions(
          mileage: 50000,
          annual: 6000,
          ownership: 80,
          fund: 1000000,
          age: 66,
          reserve: 3000000,
        ),
      );
      expect(find.text('80歳まで乗る計画'), findsOneWidget);
      expect(find.text('66歳までに大型修理用として3,000,000円を備える'), findsNothing);
      expect(find.byKey(const ValueKey('home-update')), findsOneWidget);
      expect(plan.timelinePending, isTrue);
      expect(plan.reservePending, isTrue);
    },
  );

  testWidgets(
    'empty, decimal, negative, invalid text and range errors never partially apply',
    (tester) async {
      final plan = session();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await enter(tester, 'annualMileage', '6000');
      for (final invalid in [
        '',
        '-1',
        '1.5',
        'abc',
        '1,2',
        '1000000001',
        '999999999999999999999999999999',
      ]) {
        await enter(tester, 'fund', invalid);
        await apply(tester);
        expect(
          find.byKey(const ValueKey('error-fund')),
          findsOneWidget,
          reason: invalid,
        );
        expect(plan.conditions, conditions());
        expect(plan.timelinePending, isFalse);
      }
      for (final field in [
        'currentMileage',
        'annualMileage',
        'fund',
        'reserve',
      ]) {
        await enter(tester, field, '0');
      }
      await apply(tester);
      expect(
        plan.conditions,
        conditions(mileage: 0, annual: 0, fund: 0, reserve: 0),
      );
      expect(find.text('70歳まで乗る計画'), findsOneWidget);
    },
  );

  testWidgets(
    'focus loss validates and formats, typing does not show premature errors',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();
      await openSettings(tester);
      await enter(tester, 'currentMileage', 'bad');
      expect(find.byKey(const ValueKey('error-currentMileage')), findsNothing);
      await tester.ensureVisible(input('annualMileage'));
      await tester.pumpAndSettle();
      await tester.tap(input('annualMileage'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('error-currentMileage')),
        findsOneWidget,
      );
      await enter(tester, 'currentMileage', '123456');
      await tester.ensureVisible(input('annualMileage'));
      await tester.pumpAndSettle();
      await tester.tap(input('annualMileage'));
      await tester.pump();
      expect(
        tester.widget<TextField>(input('currentMileage')).controller!.text,
        '123,456',
      );
      expect(find.byKey(const ValueKey('error-currentMileage')), findsNothing);
    },
  );

  testWidgets(
    'lower ownership retains invalid reserve draft and blocks apply',
    (tester) async {
      final plan = session();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tester.ensureVisible(input('ownershipAge'));
      await tester.tap(input('ownershipAge'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('age-option-60')));
      await tester.tap(find.byKey(const ValueKey('age-option-60')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, '65歳'), findsOneWidget);
      expect(
        find.byKey(ValueKey('error-${PlanField.reserveAge.name}')),
        findsOneWidget,
      );
      await apply(tester);
      expect(plan.conditions, conditions());
      await tester.ensureVisible(input('reserveAge'));
      await tester.tap(input('reserveAge'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('age-option-65')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('age-option-60')));
      await tester.pumpAndSettle();
      await apply(tester);
      expect(plan.conditions, conditions(ownership: 60, age: 60));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '360px scale 3 keyboard, long errors and maximum amounts remain usable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final plan = session(
        initial: conditions(
          mileage: 2000000,
          annual: 200000,
          fund: 1000000000,
          reserve: 1000000000,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(3)),
            child: child!,
          ),
          home: testApp(session: plan),
        ),
      );
      await tester.pumpAndSettle();
      await openSettings(tester);
      for (final field in [
        'currentMileage',
        'annualMileage',
        'fund',
        'reserve',
      ]) {
        await tester.ensureVisible(input(field));
        await tester.pumpAndSettle();
        final widget = tester.widget<TextField>(input(field));
        expect(widget.maxLines, isNull);
        expect(tester.takeException(), isNull);
      }
      await enter(tester, 'reserve', '1000000001');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await apply(tester);
      final error = find.byKey(const ValueKey('error-reserve'));
      await tester.ensureVisible(error);
      await tester.pumpAndSettle();
      final rect = tester.getRect(error);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
      await enter(tester, 'reserve', '1000000000');
      await apply(tester);
      expect(find.text('70歳まで乗る計画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
