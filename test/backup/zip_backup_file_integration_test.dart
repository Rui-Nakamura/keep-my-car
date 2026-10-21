import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/backup/zip_backup_codec.dart';
import 'package:keep_my_car/backup/zip_backup_transfer.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/photo/photo_file_storage.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import '../persistence_app_support.dart';
import '../photo/photo_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keep_my_car/backup_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('real JPEG files and Safe Save with deployment validator export/import/restart', () async {
    final root = await Directory.systemTemp.createTemp('kmc-zip-integration-');
    final repo = KeepMyCarRepository(
      IoLocalFileStorage(directory: () async => root),
    );
    var sequence = 0;
    final photos = PhotoLibrary(
      storage: IoPhotoFileStorage(directory: () async => root),
      processor: StoredJpegProcessor(),
      newId: () => [photoA, photoB][sequence++],
    );
    final state = PersistentPlanState(
      repository: repo,
      photos: photos,
      referenceMonth: const YearMonth(2026, 10),
    );
    final transfer = ZipBackupTransfer(state: state);
    Uint8List? exported;
    try {
      await repo.save(sampleSnapshot());
      await state.load();
      final input = await const ZipBackupCodec().encode(
        sampleSnapshot(),
        jpeg: smallJpeg(),
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'read') return {'status': 'success', 'bytes': input};
        exported = call.arguments['bytes'] as Uint8List;
        return {'status': 'success'};
      });
      final read = await transfer.readImport();
      expect(
        (await transfer.confirmImport(read.token!)).status,
        ZipTransferStatus.success,
      );
      expect(state.photoId, photoA);
      expect(
        await File('${root.path}/photos/$photoA.jpg').readAsBytes(),
        smallJpeg(),
      );
      final ready = await transfer.prepareExport();
      expect(
        (await transfer.writeExport(ready.token!)).status,
        ZipTransferStatus.success,
      );
      expect(exported, isNotNull);
      final second = await transfer.readImport();
      expect(
        (await transfer.confirmImport(second.token!)).status,
        ZipTransferStatus.success,
      );
      expect(state.photoId, photoB);
      await state.load();
      expect(state.photoId, photoB);
      expect(await photos.read(photoB), smallJpeg());
      expect(
        await photos.read(photoA),
        smallJpeg(),
      ); // backup still refers to A
      await File('${root.path}/keep_my_car.json').writeAsString('{broken');
      await state.load();
      expect(state.phase, StartupPhase.recovered);
      expect(state.photoId, photoA);
      expect(await photos.read(photoA), smallJpeg());
      expect(
        await state.cleanupPhotos(),
        false,
      ); // corrupt current inhibits deletion
    } finally {
      transfer.dispose();
      state.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      final actual = await root.resolveSymbolicLinks();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      if (!actual.startsWith(
        '$temp${Platform.pathSeparator}kmc-zip-integration-',
      )) {
        throw StateError('Unsafe cleanup');
      }
      await root.delete(recursive: true);
    }
  });
}
