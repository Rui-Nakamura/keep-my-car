import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import 'persistence/keep_my_car_repository_test.dart' show bytes;
import 'persistence_app_test.dart' show fillSetup, tapVisible;
import 'photo/photo_test_support.dart';
import 'step15_e1_test.dart' show MemoryStorage;

void main() {
  testWidgets(
    'photo-enabled App setup, edits, JSON backup and reload await cleanup',
    (tester) async {
      final storage = MemoryStorage();
      final repository = KeepMyCarRepository(storage);
      final photoStorage = MemoryPhotos()..files[photoD] = smallJpeg();
      // Match main's validation-only processor without a raw-photo profile.
      final photos = PhotoLibrary(
        storage: photoStorage,
        processor: StoredJpegProcessor(),
      );
      late PersistentPlanState state;
      final cleanupBusy = <bool>[];
      photoStorage.onCleanup = () async {
        cleanupBusy.add(!state.canRestoreBackup);
        await Future<void>.value();
      };
      const channel = MethodChannel('keep_my_car/backup_file');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Uint8List? exported;
      final fileCalls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        fileCalls.add(call.method);
        if (call.method == 'save') {
          exported = call.arguments['bytes'] as Uint8List;
          return {'status': 'success'};
        }
        return {'status': 'success', 'bytes': exported!};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        KeepMyCarApp(
          repository: repository,
          photos: photos,
          now: () => DateTime(2026, 9, 30),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic app = tester.state(find.byType(KeepMyCarApp));
      state = app.state as PersistentPlanState;
      expect(state.photos, same(photos));
      expect(app.zipTransfer.state, same(state));

      await tapVisible(tester, find.text('新しく設定する'));
      await fillSetup(tester);
      await tapVisible(tester, find.byKey(const ValueKey('setup-save')));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.car!.name, '私の愛車');
      expect(state.session!.plannedExpenses, isEmpty);
      expect(photoStorage.sweeps, hasLength(1));
      expect(photoStorage.files.containsKey(photoD), false);
      expect(state.canRestoreBackup, true);

      await tapVisible(tester, find.text('＋ 予定費を追加'));
      await tester.enterText(
        find.byKey(const ValueKey('expense-input-name')),
        '写真管理構成の予定費',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expense-input-amount')),
        '12345',
      );
      await tapVisible(tester, find.byKey(const ValueKey('save-expense')));
      expect(state.session!.plannedExpenses.single.name, '写真管理構成の予定費');
      expect(state.session!.plannedExpenses.single.amountYen, 12345);
      expect(photoStorage.sweeps, hasLength(2));
      expect(state.canRestoreBackup, true);

      await tapVisible(tester, find.text('愛車名を編集'));
      await tester.enterText(
        find.byKey(const ValueKey('car-name-input')),
        '写真管理構成の愛車',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
      expect(state.car!.name, '写真管理構成の愛車');
      expect(photoStorage.sweeps, hasLength(3));
      expect(state.canRestoreBackup, true);
      final formalBytes = bytes(state.snapshot);

      await tapVisible(tester, find.text('設定'));
      await tapVisible(tester, find.text('データ管理'));
      await tapVisible(tester, find.text('データを書き出す'));
      expect(exported, isNotNull);
      final backup =
          const BackupV1Codec().decode(exported!) as BackupImportSuccess;
      expect(bytes(backup.data), formalBytes);
      expect(photoStorage.sweeps, hasLength(3)); // Export does not save.
      final previousSession = state.session;

      await tapVisible(tester, find.text('バックアップから復元する'));
      await tapVisible(tester, find.widgetWithText(TextButton, 'バックアップから復元する'));
      expect(fileCalls, ['save', 'read']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.session, isNot(same(previousSession)));
      expect(photoStorage.sweeps, hasLength(4));
      expect(cleanupBusy, [true, true, true, true]);
      expect(storage.mutations.where((op) => op == 'temp'), hasLength(4));
      expect(state.canRestoreBackup, true);
      expect(bytes(state.snapshot), formalBytes);
      expect(storage.files[DataFile.current], formalBytes);

      await state.load();
      await tester.pumpAndSettle();
      final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(state.phase, StartupPhase.ready);
      expect(state.photoId, null);
      expect(state.photos, same(photos));
      expect(home.car.name, '写真管理構成の愛車');
      expect(home.session.plannedExpenses.single.id, 1);
      expect(
        home.session.plannedExpenses.single.plannedMonth,
        const YearMonth(2026, 9),
      );
      expect(bytes(state.snapshot), formalBytes);
      expect(bytes((await repository.load() as Loaded).data), formalBytes);
      expect(photoStorage.sweeps, hasLength(4)); // Reload does not save.
      expect(find.text(SaveRequestFailure.message), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
