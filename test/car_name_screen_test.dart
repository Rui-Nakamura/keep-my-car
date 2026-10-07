import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/domain/car_validation.dart';
import 'package:keep_my_car/features/car/presentation/car_name_screen.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import 'plan_test_support.dart';
import 'plan_settings_screen_test.dart' as settings;

final nameInput = find.byKey(const ValueKey('car-name-input'));
HomeScreen home(WidgetTester tester) =>
    tester.widget<HomeScreen>(find.byType(HomeScreen, skipOffstage: false));
Future<void> openEditor(WidgetTester tester) async {
  final button = find.widgetWithText(TextButton, '愛車名を編集');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
}

void main() {
  for (final control in ['\r', '\n', '\r\n', '\t']) {
    testWidgets('input and paste remove control ${control.codeUnits}', (
      tester,
    ) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();
      final original = home(tester).car;
      expect(
        home(tester).onSaveCarName('愛車$control名前'),
        CarNameError.invalidCharacters,
      );
      expect(home(tester).car, same(original));
      await openEditor(tester);
      await tester.enterText(nameInput, '愛車$control名前');
      expect(tester.widget<TextField>(nameInput).controller!.text, '愛車名前');
      expect(home(tester).car, same(original));
      await save(tester);
      expect(home(tester).car.name, '愛車名前');

      await openEditor(tester);
      await tester.enterText(nameInput, '');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'メルセデス$control AMG E53'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      await editable.pasteText(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(
        tester.widget<TextField>(nameInput).controller!.text,
        'メルセデス AMG E53',
      );
      await save(tester);
      expect(home(tester).car.name, 'メルセデス AMG E53');
    });
  }
  testWidgets('domain rejection uses the control-character error message', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    await openEditor(tester);
    // Bypass formatters to exercise the shared validation's defensive path.
    tester.widget<TextField>(nameInput).controller!.text = '愛車\n名前';
    await save(tester);
    expect(find.text('愛車表示名に改行やタブは使用できません'), findsOneWidget);
    expect(home(tester).car.name, 'メルセデスAMG E53');
  });
  testWidgets(
    'explicit edit, draft, normalized save and feedback preserve plan',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      plan.apply(conditions(annual: 6000, reserve: 3000000));
      final timeline = plan.timeline;
      final reserve = plan.reserveResult;
      final delta = plan.reserveDeltaYen;
      final notice = plan.homeUpdate;
      calls.reset();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      expect(find.text('メルセデスAMG E53'), findsOneWidget);
      await tester.tap(find.text('メルセデスAMG E53'));
      await tester.pumpAndSettle();
      expect(find.byType(CarNameScreen), findsNothing);
      final before = home(tester).car;
      await openEditor(tester);
      expect(tester.widget<TextField>(nameInput).controller!.text, before.name);
      await tester.enterText(nameInput, '　 私の　愛車 E53  ');
      expect(home(tester).car, same(before));
      await save(tester);
      expect(home(tester).car.name, '私の　愛車 E53');
      expect(find.text('私の　愛車 E53'), findsOneWidget);
      expect(find.text('愛車名を更新しました'), findsOneWidget);
      expect((calls.timeline, calls.reserve), (0, 0));
      expect(plan.timeline, same(timeline));
      expect(plan.reserveResult, same(reserve));
      expect((plan.timelinePending, plan.reservePending), (true, true));
      expect(plan.reserveDeltaYen, delta);
      expect(plan.homeUpdate, notice);
      expect(home(tester).car.annualMileageKm, 6000);
      expect(home(tester).car.mileageCheckedMonth, before.mileageCheckedMonth);
    },
  );

  testWidgets(
    'unchanged saves preserve car identity, calculations and feedback',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      plan.apply(conditions(annual: 6000, reserve: 3000000));
      final notice = plan.homeUpdate;
      final delta = plan.reserveDeltaYen;
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      final original = home(tester).car;
      calls.reset();
      for (final value in [original.name, '　 ${original.name}  ']) {
        await openEditor(tester);
        await tester.enterText(nameInput, value);
        await save(tester);
        expect(home(tester).car, same(original));
        expect(find.text('愛車名を更新しました'), findsNothing);
        expect((calls.timeline, calls.reserve), (0, 0));
        expect((plan.timelinePending, plan.reservePending), (true, true));
        expect(plan.homeUpdate, notice);
        expect(plan.reserveDeltaYen, delta);
      }
    },
  );

  testWidgets('invalid input and both back paths preserve formal car', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    final original = home(tester).car;
    for (final androidBack in [false, true]) {
      await openEditor(tester);
      for (final invalid in ['', '　 ', '車' * 41]) {
        await tester.enterText(nameInput, invalid);
        await save(tester);
        expect(find.byKey(const ValueKey('car-name-error')), findsOneWidget);
        expect(home(tester).car, same(original));
      }
      await tester.enterText(nameInput, '破棄する名前');
      if (androidBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byType(BackButton));
      }
      await tester.pumpAndSettle();
      expect(home(tester).car, same(original));
      expect(find.text('愛車名を更新しました'), findsNothing);
    }
  });

  testWidgets(
    'formal update also validates; valid settings synchronize mileage',
    (tester) async {
      final plan = session();
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      final original = home(tester).car;
      expect(home(tester).onSaveCarName('　'), CarNameError.required);
      expect(home(tester).onSaveCarName('車' * 41), CarNameError.tooLong);
      expect(home(tester).car, same(original));
      await openEditor(tester);
      await tester.enterText(nameInput, '新しい名前');
      await save(tester);
      await settings.openSettings(tester);
      await settings.enter(tester, 'currentMileage', '50000');
      await settings.enter(tester, 'annualMileage', '6000');
      await settings.enter(tester, 'fund', '-1');
      await settings.apply(tester);
      expect(home(tester).car.currentMileageKm, 45000);
      expect(home(tester).car.annualMileageKm, 4000);
      await settings.enter(tester, 'fund', '500000');
      await settings.apply(tester);
      final car = home(tester).car;
      expect(car.name, '新しい名前');
      expect(car.currentMileageKm, plan.conditions.currentMileageKm);
      expect(car.currentMileageKm, 50000);
      expect(car.annualMileageKm, plan.conditions.annualMileageKm);
      expect(car.annualMileageKm, 6000);
      expect(
        car.firstRegistrationMonth,
        goldenSample.car.firstRegistrationMonth,
      );
      expect(car.mileageCheckedMonth, goldenSample.car.mileageCheckedMonth);
    },
  );

  for (final scale in [1.0, 3.0]) {
    for (final longName in ['車' * 40, 'A' * 40]) {
      testWidgets('360px scale $scale long name ${longName[0]} and keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
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
        final edit = find.widgetWithText(TextButton, '愛車名を編集');
        expect(tester.getSize(edit).height, greaterThanOrEqualTo(48));
        await openEditor(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.enterText(nameInput, '車' * 41);
        await save(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('car-name-error')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(nameInput);
        await tester.enterText(nameInput, longName);
        expect(tester.widget<TextField>(nameInput).maxLines, isNull);
        await save(tester);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final label = find.text(longName);
        expect(label, findsOneWidget);
        final text = tester.widget<Text>(label);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        for (final value in [
          longName,
          '愛車名を編集',
          '未来タイムラインを見る',
          '＋ 予定費を追加',
          'すべて見る',
          '設定',
        ]) {
          await tester.ensureVisible(find.text(value));
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.text(value));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
        }
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(state.position.axis, Axis.vertical);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
