import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/screen_success_feedback.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/backup_file/backup_file_gateway.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/initial_setup/presentation/initial_setup_screen.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'persistence_app_support.dart';
import 'persistence_app_test.dart' show tapVisible;

class ThrowingGateway extends BackupFileGateway {
  @override
  Future<BackupFileResult> read() async => throw StateError('unexpected');
}

void main() {
  const channel = MethodChannel('keep_my_car/backup_file');
  final restored = sampleSnapshot();
  final bytes = const BackupV1Codec().encode(
    restored,
    createdAt: DateTime(2026, 10),
  );
  late TestRepository repo;
  late Object response;
  int fileCalls = 0;

  setUp(() {
    response = {'status': 'success', 'bytes': bytes};
    fileCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          fileCalls++;
          return call.method == 'save' &&
                  (response as Map)['status'] == 'success'
              ? {'status': 'success'}
              : response;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> boot(
    WidgetTester tester,
    LoadResult result, {
    BackupFileGateway? gateway,
  }) async {
    repo = TestRepository(result);
    await tester.pumpWidget(
      KeepMyCarApp(
        repository: repo,
        backupGateway: gateway,
        now: () => DateTime(2026, 10),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> management(WidgetTester tester) async {
    await tapVisible(tester, find.text('設定'));
    await tapVisible(tester, find.text('データ管理'));
  }

  Future<void> restore(WidgetTester tester) =>
      tapVisible(tester, find.text('バックアップから復元する'));
  Future<void> accept(WidgetTester tester) =>
      tapVisible(tester, find.widgetWithText(TextButton, 'バックアップから復元する'));

  int notificationId(WidgetTester tester) => tester
      .widget<ScreenSuccessFeedback>(
        find.byType(ScreenSuccessFeedback, skipOffstage: false),
      )
      .notificationId;

  for (final status in ['success', 'cancelled', 'error']) {
    testWidgets('normal export $status leaves formal data unchanged', (
      tester,
    ) async {
      await boot(tester, Loaded(restored));
      final before = tester.widget<HomeScreen>(find.byType(HomeScreen));
      response = {'status': status, if (status == 'error') 'code': 'ioFailure'};
      await management(tester);
      await tapVisible(tester, find.text('データを書き出す'));
      expect(fileCalls, 1);
      expect(repo.saves, isEmpty);
      final after = tester.widget<HomeScreen>(
        find.byType(HomeScreen, skipOffstage: false),
      );
      expect(after.car, same(before.car));
      expect(after.session, same(before.session));
      expect(notificationId(tester), 0);
      expect(
        find.text('データを書き出しました'),
        status == 'success' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('処理を完了できませんでした。もう一度お試しください'),
        status == 'error' ? findsOneWidget : findsNothing,
      );
    });
  }
  for (final failure in [false, true]) {
    for (final action in ['cancel', 'success', 'saveError', 'uncertain']) {
      testWidgets('restore failure=$failure $action confirms then commits', (
        tester,
      ) async {
        await boot(
          tester,
          failure ? LoadFailure([saveFailure().issue]) : Loaded(restored),
        );
        if (!failure) await management(tester);
        repo.saveResult = action == 'saveError' || action == 'uncertain'
            ? saveFailure(uncertain: action == 'uncertain')
            : const Saved();
        await restore(tester);
        expect(find.text('バックアップから復元しますか？'), findsOneWidget);
        expect(
          find.text(
            failure
                ? '現在読み込めない保存データは、選択したバックアップの内容に置き換わり、元に戻せません。'
                : '現在のデータは、選択したバックアップの内容に置き換わります。',
          ),
          findsOneWidget,
        );
        expect(repo.saves, isEmpty);
        if (action == 'cancel') {
          await tapVisible(tester, find.text('キャンセル'));
          expect(repo.saves, isEmpty);
        } else {
          await accept(tester);
          expect(repo.saves, hasLength(1));
        }
        if (action == 'success') {
          expect(notificationId(tester), 1);
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(find.text('データ管理'), findsNothing);
          expect(find.text('バックアップから復元しました'), findsOneWidget);
        } else if (action == 'uncertain') {
          expect(notificationId(tester), 0);
          expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
          expect(find.text('保存状態を確認する'), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          expect(find.text('バックアップから復元しました'), findsNothing);
        } else if (failure) {
          expect(find.text('保存データを読み込めませんでした'), findsOneWidget);
        }
        if (action == 'saveError') {
          expect(find.text('処理を完了できませんでした。もう一度お試しください'), findsOneWidget);
        }
        if (action != 'success') expect(notificationId(tester), 0);
      });
    }
  }
  for (final toFailure in [true, false]) {
    testWidgets('restore reconfirms changed phase toFailure=$toFailure', (
      tester,
    ) async {
      await boot(
        tester,
        toFailure ? Loaded(restored) : LoadFailure([saveFailure().issue]),
      );
      if (toFailure) await management(tester);
      await restore(tester);
      expect(repo.saves, isEmpty);
      // Simulate an external phase update during the first confirmation.
      // Only the app-owned public state is accessed; assertions use UI and saves.
      final dynamic app = tester.state(find.byType(KeepMyCarApp));
      final state = app.state as PersistentPlanState;
      state.phase = toFailure ? StartupPhase.failure : StartupPhase.ready;
      await accept(tester);
      expect(repo.saves, isEmpty);
      expect(fileCalls, 1);
      expect(
        find.text(
          toFailure
              ? '現在読み込めない保存データは、選択したバックアップの内容に置き換わり、元に戻せません。'
              : '現在のデータは、選択したバックアップの内容に置き換わります。',
        ),
        findsOneWidget,
      );
      await accept(tester);
      expect(repo.saves, hasLength(1));
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }

  testWidgets(
    'Failure prioritizes restore and distinguishes destructive confirmation',
    (tester) async {
      await boot(tester, LoadFailure([saveFailure().issue]));
      final restoreButton = find.widgetWithText(FilledButton, 'バックアップから復元する');
      final newButton = find.widgetWithText(OutlinedButton, '新しく設定する');
      expect(restoreButton, findsOneWidget);
      expect(newButton, findsOneWidget);
      expect(
        tester.getTopLeft(restoreButton).dy,
        lessThan(tester.getTopLeft(newButton).dy),
      );
      await tapVisible(tester, newButton);
      expect(find.widgetWithText(TextButton, 'キャンセル'), findsOneWidget);
      final deleteButton = find.widgetWithText(FilledButton, '削除して新しく設定する');
      expect(deleteButton, findsOneWidget);
      final button = tester.widget<FilledButton>(deleteButton);
      final colors = Theme.of(tester.element(deleteButton)).colorScheme;
      expect(button.style!.backgroundColor!.resolve({}), colors.error);
      expect(button.style!.foregroundColor!.resolve({}), colors.onError);
      expect(repo.discards, 0);
    },
  );

  for (final issue in [
    'notBackup',
    'version',
    'content',
    'tooLarge',
    'cancelled',
    'unexpected',
  ]) {
    testWidgets('import $issue never shows replacement confirmation', (
      tester,
    ) async {
      await boot(
        tester,
        issue == 'cancelled' ? const NoData() : Loaded(restored),
        gateway: issue == 'unexpected' ? ThrowingGateway() : null,
      );
      if (issue != 'cancelled') await management(tester);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (issue == 'notBackup') json['format'] = 'other';
      if (issue == 'version') json['exportFormatVersion'] = 2;
      if (issue == 'content') json.remove('data');
      response = issue == 'cancelled'
          ? {'status': 'cancelled'}
          : issue == 'tooLarge'
          ? {'status': 'error', 'code': 'tooLarge'}
          : {
              'status': 'success',
              'bytes': Uint8List.fromList(utf8.encode(jsonEncode(json))),
            };
      await restore(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.saves, isEmpty);
      expect(notificationId(tester), 0);
      expect(
        find.text(issue == 'cancelled' ? '新しく設定する' : 'データ管理'),
        findsOneWidget,
      );
      final message = switch (issue) {
        'notBackup' => 'このファイルはKeep My Carのバックアップではありません',
        'version' => 'このバックアップは新しいバージョンで作成されているため、このアプリでは読み込めません',
        'content' || 'tooLarge' => 'バックアップファイルを読み込めませんでした',
        'unexpected' => '処理を完了できませんでした。もう一度お試しください',
        _ => null,
      };
      if (message != null) expect(find.text(message), findsOneWidget);
      if (message == null) expect(find.byType(SnackBar), findsNothing);
    });
  }
  testWidgets('NoData restore bypasses setup and confirmation', (tester) async {
    await boot(tester, const NoData());
    await restore(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(InitialSetupScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(notificationId(tester), 1);
    final saved = repo.saves.single.plannedExpenses;
    expect(
      saved.map(
        (e) => (
          e.id,
          e.name,
          e.amountYen,
          e.plannedMonth,
          e.basis,
          e.memo,
          e.status,
        ),
      ),
      restored.plannedExpenses.map(
        (e) => (
          e.id,
          e.name,
          e.amountYen,
          e.plannedMonth,
          e.basis,
          e.memo,
          e.status,
        ),
      ),
    );
  });
  for (final action in ['cancel', 'success', 'error', 'uncertain']) {
    testWidgets('Failure new setup $action only discards after confirmation', (
      tester,
    ) async {
      await boot(tester, LoadFailure([saveFailure().issue]));
      repo.discardResult = action == 'error' || action == 'uncertain'
          ? saveFailure(uncertain: action == 'uncertain')
          : const Saved();
      await tapVisible(tester, find.text('新しく設定する'));
      expect(repo.discards, 0);
      expect(find.text('現在読み込めない保存データは削除され、元に戻せません。'), findsOneWidget);
      await tapVisible(
        tester,
        find.text(action == 'cancel' ? 'キャンセル' : '削除して新しく設定する'),
      );
      expect(repo.discards, action == 'cancel' ? 0 : 1);
      expect(repo.saves, isEmpty);
      if (action == 'success') {
        expect(find.byType(InitialSetupScreen), findsOneWidget);
      }
      if (action == 'cancel' || action == 'error') {
        expect(find.text('保存データを読み込めませんでした'), findsOneWidget);
      }
      if (action == 'uncertain') {
        expect(find.text('保存状態を確認できませんでした'), findsOneWidget);
        expect(find.text('保存状態を確認する'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      }
      if (action == 'error') {
        expect(find.text('処理を完了できませんでした。もう一度お試しください'), findsOneWidget);
      }
    });
  }
  for (final phase in ['noData', 'failure', 'ready']) {
    testWidgets('backup UI and confirmation at 360px scale 3: $phase', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await boot(
        tester,
        phase == 'ready'
            ? Loaded(restored)
            : phase == 'failure'
            ? LoadFailure([saveFailure().issue])
            : const NoData(),
      );
      if (phase == 'ready') await management(tester);
      await restore(tester);
      if (phase != 'noData') {
        await accept(tester);
      }
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('NoData failed restore retains startup choices', (tester) async {
    await boot(tester, const NoData());
    repo.saveResult = saveFailure();
    await restore(tester);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('新しく設定する'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(notificationId(tester), 0);
  });

  testWidgets('safe save must finish before Home or success notice', (
    tester,
  ) async {
    await boot(tester, const NoData());
    final pending = Completer<SaveResult>();
    repo.onSave = (_) => pending.future;
    await restore(tester);
    expect(find.byType(HomeScreen), findsNothing);
    expect(notificationId(tester), 0);
    expect(find.text('バックアップから復元しました'), findsNothing);
    pending.complete(const Saved());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(notificationId(tester), 1);
  });

  testWidgets(
    'restored Home revisit, rebuild and fresh app never replay feedback',
    (tester) async {
      await boot(tester, Loaded(restored));
      expect(notificationId(tester), 0);
      await management(tester);
      await restore(tester);
      await accept(tester);
      expect(notificationId(tester), 1);
      expect(
        find.byKey(const ValueKey('screen-success-outline')),
        findsNothing,
      );
      await tapVisible(tester, find.text('設定'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Editing a name rebuilds the app without issuing a new success event.
      await tapVisible(tester, find.text('愛車名を編集'));
      await tester.enterText(
        find.byKey(const ValueKey('car-name-input')),
        '復元後の愛車',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
      expect(notificationId(tester), 1);
      expect(
        find.byKey(const ValueKey('screen-success-outline')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await boot(tester, Loaded(repo.saves.last));
      expect(notificationId(tester), 0);
      expect(
        find.byKey(const ValueKey('screen-success-outline')),
        findsNothing,
      );
    },
  );
}
