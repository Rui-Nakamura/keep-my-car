import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/initial_setup/presentation/initial_setup_screen.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'persistence_app_support.dart';

Future<void> boot(WidgetTester tester, TestRepository repo) async {
  await tester.pumpWidget(
    KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9, 30)),
  );
  await tester.pumpAndSettle();
  if (repo.result is NoData) {
    await tapVisible(tester, find.text('新しく設定する'));
  }
}

Future<void> fillSetup(WidgetTester tester) async {
  for (final entry in {
    'birth': '1970-04',
    'name': '私の愛車',
    'registration': '2018-08',
    'mileage': '45000',
    'annual': '4000',
    'ownership': '70',
    'reserveAge': '65',
  }.entries) {
    final input = find.byKey(ValueKey('setup-${entry.key}'));
    await tester.ensureVisible(input);
    await tester.enterText(input, entry.value);
  }
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'settings failure preserves formal car, conditions, results and draft',
    (tester) async {
      final repo = TestRepository(Loaded(sampleSnapshot()))
        ..saveResult = saveFailure();
      await boot(tester, repo);
      final before = tester.widget<HomeScreen>(find.byType(HomeScreen));
      final oldCar = before.car;
      final oldResults = before.session.timeline;
      await tapVisible(tester, find.text('設定'));
      final input = find.byKey(const ValueKey('input-currentMileage'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '50000');
      await tapVisible(tester, find.byKey(const ValueKey('apply-plan')));
      expect(find.text(SaveRequestFailure.message), findsOneWidget);
      final after = tester.widget<HomeScreen>(
        find.byType(HomeScreen, skipOffstage: false),
      );
      expect(after.car, same(oldCar));
      expect(after.session.timeline, same(oldResults));
      expect(after.session.conditions.currentMileageKm, 45000);
      expect(
        tester.widget<TextField>(input).controller!.text.replaceAll(',', ''),
        '50000',
      );
    },
  );

  for (final operation in ['add', 'edit', 'delete']) {
    testWidgets(
      'expense $operation failure leaves editor draft and formal list unchanged',
      (tester) async {
        final repo = TestRepository(Loaded(sampleSnapshot()))
          ..saveResult = saveFailure();
        await boot(tester, repo);
        final before = tester
            .widget<HomeScreen>(find.byType(HomeScreen))
            .session;
        final list = before.plannedExpenses;
        await tapVisible(tester, find.text('予定費を見る・追加する'));
        await tapVisible(
          tester,
          operation == 'add'
              ? find.text('予定費を追加')
              : find.byKey(const ValueKey('edit-expense-1')),
        );
        if (operation == 'delete') {
          await tapVisible(tester, find.text('この予定を削除'));
          await tapVisible(
            tester,
            find.byKey(const ValueKey('confirm-delete-expense')),
          );
        } else {
          final name = find.byKey(const ValueKey('expense-input-name'));
          await tester.ensureVisible(name);
          await tester.enterText(name, '保存候補');
          final amount = find.byKey(const ValueKey('expense-input-amount'));
          await tester.ensureVisible(amount);
          await tester.enterText(amount, '12345');
          await tapVisible(tester, find.byKey(const ValueKey('save-expense')));
          expect(tester.widget<TextField>(name).controller!.text, '保存候補');
        }
        expect(find.text(SaveRequestFailure.message), findsOneWidget);
        expect(before.plannedExpenses, same(list));
        expect(before.timelinePending, isFalse);
        expect(before.reservePending, isFalse);
        expect(repo.saves, hasLength(1));
      },
    );
  }

  testWidgets(
    'name save disables submit and back until persistence completes',
    (tester) async {
      final repo = TestRepository(Loaded(sampleSnapshot()));
      final pending = Completer<SaveResult>();
      repo.onSave = (_) => pending.future;
      await boot(tester, repo);
      await tapVisible(tester, find.text('愛車名を編集'));
      await tester.enterText(
        find.byKey(const ValueKey('car-name-input')),
        '保存候補',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存中…'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('car-name-input')), findsOneWidget);
      expect(find.text('愛車名を更新しました'), findsNothing);
      expect(repo.saves, hasLength(1));
      pending.complete(const Saved());
      await tester.pumpAndSettle();
      expect(find.text('保存候補'), findsOneWidget);
      expect(find.text('愛車名を更新しました'), findsOneWidget);
    },
  );
  testWidgets('Loading shows no Home or sample until NoData opens setup', (
    tester,
  ) async {
    final pending = Completer<LoadResult>();
    final repo = TestRepository(const NoData())..onLoad = () => pending.future;
    await tester.pumpWidget(
      KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
    );
    expect(find.text('データを読み込んでいます…'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('メルセデスAMG E53'), findsNothing);
    pending.complete(const NoData());
    await tester.pumpAndSettle();
    expect(find.text('バックアップから復元する'), findsOneWidget);
    await tapVisible(tester, find.text('新しく設定する'));
    expect(find.byType(InitialSetupScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('setup-checked')))
          .controller!
          .text,
      '2026-09',
    );
    for (final key in ['fund', 'reserve']) {
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('setup-$key')))
            .controller!
            .text,
        '0',
      );
    }
    for (final key in ['ownership', 'reserveAge']) {
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('setup-$key')))
            .controller!
            .text,
        isEmpty,
      );
    }
    expect(repo.saves, isEmpty);
  });

  for (final success in [false, true]) {
    testWidgets(
      'initial save success=$success holds draft until durable save',
      (tester) async {
        final repo = TestRepository(const NoData());
        final pending = Completer<SaveResult>();
        repo.onSave = (_) => pending.future;
        await boot(tester, repo);
        await fillSetup(tester);
        final button = find.byKey(const ValueKey('setup-save'));
        await tapVisible(tester, button);
        expect(find.byType(HomeScreen), findsNothing);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(repo.saves, hasLength(1));
        final data = repo.saves.single;
        expect(data.ownerBirthMonth, const YearMonth(1970, 4));
        expect(data.car.name, '私の愛車');
        expect(data.plannedExpenses, isEmpty);
        expect(data.planConditions.currentCarFundYen, 0);
        expect(data.planConditions.largeRepairReserveYen, 0);
        pending.complete(success ? const Saved() : saveFailure());
        await tester.pumpAndSettle();
        if (success) {
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(find.text('私の愛車'), findsOneWidget);
        } else {
          expect(find.byType(InitialSetupScreen), findsOneWidget);
          expect(find.text(SaveRequestFailure.message), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('setup-name')))
                .controller!
                .text,
            '私の愛車',
          );
        }
      },
    );
  }

  testWidgets('invalid initial inputs do not save', (tester) async {
    final repo = TestRepository(const NoData());
    await boot(tester, repo);
    await tapVisible(tester, find.byKey(const ValueKey('setup-save')));
    expect(repo.saves, isEmpty);
    await fillSetup(tester);
    await tester.enterText(
      find.byKey(const ValueKey('setup-reserveAge')),
      '71',
    );
    await tapVisible(tester, find.byKey(const ValueKey('setup-save')));
    expect(find.text('備え目標年齢は保有目標年齢以下にしてください。'), findsOneWidget);
    expect(repo.saves, isEmpty);
  });

  testWidgets('Loaded uses local launch month and recomputes', (tester) async {
    final repo = TestRepository(Loaded(sampleSnapshot()));
    await tester.pumpWidget(
      KeepMyCarApp(repository: repo, now: () => DateTime(2030, 3, 1)),
    );
    await tester.pumpAndSettle();
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.session.referenceMonth, const YearMonth(2030, 3));
    expect(home.session.birthMonth, const YearMonth(1970, 4));
    expect(home.session.timeline.first.year, 2030);
    expect(repo.loads, 1);
    expect(repo.saves, isEmpty);
  });

  testWidgets('Recovered displays notice without writing or repairing files', (
    tester,
  ) async {
    final repo = TestRepository(Recovered(sampleSnapshot()));
    await boot(tester, repo);
    expect(find.text('データを復元しました'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('データを復元しました'), findsNothing);
    expect(repo.saves, isEmpty);
    expect(repo.loads, 1);
  });

  testWidgets('Failure blocks Home and retries same repository', (
    tester,
  ) async {
    final repo = TestRepository(LoadFailure([saveFailure().issue]));
    await boot(tester, repo);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('バックアップから復元する'), findsOneWidget);
    repo.result = const NoData();
    await tapVisible(tester, find.text('もう一度読み込む'));
    expect(find.text('新しく設定する'), findsOneWidget);
    await tapVisible(tester, find.text('新しく設定する'));
    expect(find.byType(InitialSetupScreen), findsOneWidget);
    expect(repo.loads, 2);
  });

  for (final result in [
    Loaded(sampleSnapshot()),
    Recovered(sampleSnapshot()),
    LoadFailure([saveFailure().issue]),
    const NoData(),
  ]) {
    testWidgets(
      'uncertain save routes reload ${result.runtimeType} without success notice',
      (tester) async {
        final repo = TestRepository(Loaded(sampleSnapshot()))
          ..saveResult = saveFailure(uncertain: true);
        await boot(tester, repo);
        await tapVisible(tester, find.text('愛車名を編集'));
        await tester.enterText(
          find.byKey(const ValueKey('car-name-input')),
          '候補',
        );
        await tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
        expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
        expect(find.text('愛車名を更新しました'), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);
        repo.result = result;
        await tapVisible(tester, find.text('保存状態を確認する'));
        expect(repo.loads, 2);
        if (result is Loaded || result is Recovered) {
          expect(find.byType(HomeScreen), findsOneWidget);
        }
        if (result is Recovered) {
          expect(find.text('データを復元しました'), findsOneWidget);
        }
        if (result is NoData) {
          expect(find.text('新しく設定する'), findsOneWidget);
          await tapVisible(tester, find.text('新しく設定する'));
          expect(find.byType(InitialSetupScreen), findsOneWidget);
        }
        if (result is LoadFailure) {
          expect(find.text('保存データを読み込めませんでした'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'ordinary name failure stays editable with draft, no success notice',
    (tester) async {
      final repo = TestRepository(Loaded(sampleSnapshot()))
        ..saveResult = saveFailure();
      await boot(tester, repo);
      await tapVisible(tester, find.text('愛車名を編集'));
      await tester.enterText(
        find.byKey(const ValueKey('car-name-input')),
        '候補',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
      expect(find.text(SaveRequestFailure.message), findsOneWidget);
      expect(find.text('愛車名を更新しました'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('car-name-input')))
            .controller!
            .text,
        '候補',
      );
    },
  );

  testWidgets(
    '360px scale 3 initial form with keyboard can reach submit without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await boot(tester, TestRepository(const NoData()));
      await fillSetup(tester);
      final field = find.byKey(const ValueKey('setup-reserveAge'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getRect(field).bottom, lessThanOrEqualTo(500));
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.ensureVisible(find.byKey(const ValueKey('setup-save')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('setup-save'))).right,
        lessThanOrEqualTo(360),
      );
      expect(tester.takeException(), isNull);
      final button = tester.getRect(find.byKey(const ValueKey('setup-save')));
      expect(button.top, greaterThanOrEqualTo(0));
      expect(button.bottom, lessThanOrEqualTo(500));
      expect(button.left, greaterThanOrEqualTo(0));
    },
  );
}
