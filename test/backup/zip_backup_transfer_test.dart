import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_transfer.dart';
import 'package:keep_my_car/backup/zip_backup_codec.dart';
import 'package:keep_my_car/backup/zip_backup_result.dart';
import 'package:keep_my_car/backup/zip_backup_transfer.dart';
import 'package:keep_my_car/backup/zip_backup_worker.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/models/plan_conditions.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import '../persistence/keep_my_car_repository_test.dart'
    show HookStorage, bytes;
import '../persistence_app_support.dart';
import '../photo/photo_state_test.dart' show withId;
import '../photo/photo_test_support.dart';
import '../step15_e1_test.dart' show MemoryStorage;
import 'zip_test_support.dart';

class ObservedPhotos extends MemoryPhotos {
  Future<Uint8List?> Function(String)? onRead;
  @override
  Future<Uint8List?> read(String id) =>
      onRead == null ? super.read(id) : onRead!(id);
}

class ControlledWorker extends ZipBackupWorker {
  Future<void> Function()? beforeEncode;
  Future<void> Function()? beforeDecode;
  @override
  Future<Uint8List> encode(RestoredCarData plan, {Uint8List? jpeg}) async {
    await beforeEncode?.call();
    return super.encode(plan, jpeg: jpeg);
  }

  @override
  Future<ZipBackupDecodeResult> decode(Uint8List bytes) async {
    await beforeDecode?.call();
    return super.decode(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keep_my_car/backup_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = ZipBackupCodec();
  late MemoryStorage memory;
  late HookStorage hooks;
  late KeepMyCarRepository repository;
  late ObservedPhotos files;
  late FakeProcessor processor;
  late PhotoLibrary photos;
  late PersistentPlanState state;
  late ZipBackupTransfer transfer;
  late ControlledWorker worker;
  late Uint8List input;
  Uint8List? output;
  var saves = 0;
  late RestoredCarData original;
  late RestoredCarData imported;

  setUp(() async {
    original = withId(sampleSnapshot(), photoA);
    final base = sampleSnapshot();
    imported = (
      photoId: null,
      ownerBirthMonth: base.ownerBirthMonth,
      car: base.car.copyWith(name: 'ZIP restored'),
      planConditions: base.planConditions,
      plannedExpenses: base.plannedExpenses,
    );
    memory = MemoryStorage()..files[DataFile.current] = bytes(original);
    hooks = HookStorage(memory);
    repository = KeepMyCarRepository(hooks);
    files = ObservedPhotos()..files[photoA] = smallJpeg();
    processor = FakeProcessor();
    var next = 0;
    photos = PhotoLibrary(
      storage: files,
      processor: processor,
      newId: () => [photoB, photoC, photoD][next++],
    );
    state = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 10),
      photos: photos,
    );
    await state.load();
    original = state.snapshot;
    worker = ControlledWorker();
    transfer = ZipBackupTransfer(state: state, worker: worker);
    input = await codec.encode(imported, jpeg: smallJpeg());
    output = null;
    saves = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        expect(call.arguments, {'profile': 'zipV1'});
        return {'status': 'success', 'bytes': input};
      }
      saves++;
      expect(call.arguments['mimeType'], 'application/zip');
      expect(call.arguments['filename'], endsWith('.zip'));
      output = call.arguments['bytes'] as Uint8List;
      return {'status': 'success'};
    });
  });
  tearDown(() {
    transfer.dispose();
    state.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<ZipBackupToken> candidate() async {
    final read = await transfer.readImport();
    expect(read.status, ZipTransferStatus.importConfirmation);
    expect(read.plan!.car.name, 'ZIP restored');
    expect(state.snapshot, original);
    return read.token!;
  }

  for (final hasPhoto in [false, true]) {
    test('export captured plan and photo: $hasPhoto', () async {
      if (!hasPhoto) await state.deletePhoto();
      final before = state.snapshot;
      final generation = state.generation;
      final ready = await transfer.prepareExport();
      expect(ready.status, ZipTransferStatus.exportReady);
      expect(ready.hasPhoto, hasPhoto);
      expect(saves, 0);
      expect(
        (await transfer.writeExport(ready.token!)).status,
        ZipTransferStatus.success,
      );
      final zip = await codec.decode(output!) as ZipBackupSuccess;
      expect(zip.plan.car.name, before.car.name);
      expect(zip.jpeg, hasPhoto ? smallJpeg() : null);
      expect(zip.plan.photoId, null);
      expect(state.snapshot, before);
      expect(state.generation, generation);
      expect(
        (await transfer.writeExport(ready.token!)).status,
        ZipTransferStatus.conflict,
      );
    });

    test('import complete replacement and restart: $hasPhoto', () async {
      input = await codec.encode(imported, jpeg: hasPhoto ? smallJpeg() : null);
      final token = await candidate();
      expect(
        (await transfer.confirmImport(token)).status,
        ZipTransferStatus.success,
      );
      expect(state.car!.name, 'ZIP restored');
      expect(state.photoId, hasPhoto ? photoB : null);
      expect(
        state.session!.plannedExpenses.map((e) => e.id),
        imported.plannedExpenses.map((e) => e.id),
      );
      expect(
        state.session!.plannedExpenses.map((e) => e.memo),
        imported.plannedExpenses.map((e) => e.memo),
      );
      expect(state.session!.conditions, imported.planConditions);
      expect(processor.paths, isEmpty); // no conversion/recompression
      expect(files.files.containsKey(photoA), true); // backup reference
      if (hasPhoto) expect(await photos.read(photoB), smallJpeg());
      final reloaded = await repository.load() as Loaded;
      expect(reloaded.data.photoId, state.photoId);
      expect(reloaded.data.car.name, 'ZIP restored');
      expect(
        (await transfer.confirmImport(token)).status,
        ZipTransferStatus.conflict,
      );
      memory.files[DataFile.current] = [42];
      await state.load();
      expect(state.phase, StartupPhase.recovered);
      expect(state.photoId, photoA);
      expect(await photos.read(photoA), smallJpeg());
    });
  }

  for (final status in [BackupPhotoStatus.missing, BackupPhotoStatus.corrupt]) {
    for (final approve in [false, true]) {
      test('$status omission requires explicit approval $approve', () async {
        files.files.remove(photoA);
        if (status == BackupPhotoStatus.corrupt) {
          files.files[photoA] = Uint8List.fromList([1]);
        }
        final ready = await transfer.prepareExport();
        expect(ready.status, ZipTransferStatus.photoConfirmation);
        expect(ready.photoStatus, status);
        expect(saves, 0);
        final result = await transfer.writeExport(
          ready.token!,
          approvePhotoOmission: approve,
        );
        expect(
          result.status,
          approve ? ZipTransferStatus.success : ZipTransferStatus.cancelled,
        );
        expect(saves, approve ? 1 : 0);
        expect(state.snapshot, original);
        if (approve) {
          expect((await codec.decode(output!) as ZipBackupSuccess).jpeg, null);
        }
      });
    }
  }

  for (final issue in ['io', 'unsafe', 'unsupported', 'bug']) {
    test('photo $issue is error, never omission confirmation', () async {
      files.onRead = (_) async => throw switch (issue) {
        'io' => const FileSystemException('injected'),
        'unsafe' => const PhotoFailure(PhotoIssue.unsafePath),
        'unsupported' => const PhotoFailure(PhotoIssue.unsupported),
        _ => StateError('injected'),
      };
      final ready = await transfer.prepareExport();
      expect(ready.status, ZipTransferStatus.error);
      expect(ready.token, null);
      expect(saves, 0);
      expect(state.snapshot, original);
    });
  }

  test('missing PhotoLibrary rejects photo export and import', () async {
    transfer.dispose();
    final other = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 10),
    );
    await other.load();
    final backup = ZipBackupTransfer(state: other);
    expect(
      (await backup.prepareExport()).photoStatus,
      BackupPhotoStatus.unavailable,
    );
    final read = await backup.readImport();
    expect(
      (await backup.confirmImport(read.token!)).photoStatus,
      BackupPhotoStatus.unavailable,
    );
    expect(bytes(other.snapshot), bytes(original));
    backup.dispose();
    other.dispose();
  });

  test('export snapshot survives expense edit, photo deletion and cleanup during worker', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    worker.beforeEncode = () async {
      entered.complete();
      await release.future;
    };
    final ready = await transfer.prepareExport();
    final writing = transfer.writeExport(ready.token!);
    await entered.future;
    await state.saveExpense(
      name: 'later',
      month: const YearMonth(2026, 11),
      amountYen: 12,
    );
    await state.deletePhoto();
    await state.saveCarName('latest'); // rotate backup past old reference
    await state.cleanupPhotos();
    expect(
      files.files.containsKey(photoA),
      false,
    ); // lease released after bytes captured
    release.complete();
    expect((await writing).status, ZipTransferStatus.success);
    final zip = await codec.decode(output!) as ZipBackupSuccess;
    expect(zip.plan.car.name, original.car.name);
    expect(zip.plan.plannedExpenses.length, original.plannedExpenses.length);
    expect(zip.jpeg, smallJpeg());
  });

  test('export protects photo while read and cleanup overlap', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onRead = (id) async {
      entered.complete();
      await release.future;
      return files.files[id];
    };
    final preparing = transfer.prepareExport();
    await entered.future;
    await state.deletePhoto();
    await state.saveCarName('rotate');
    expect(files.files.containsKey(photoA), true);
    release.complete();
    expect((await preparing).status, ZipTransferStatus.conflict);
    transfer.cancel();
    await state.cleanupPhotos();
    expect(files.files.containsKey(photoA), false);
  });

  for (final outcome in ['cancelled', 'ioFailure', 'interrupted', 'timeout']) {
    test(
      'external save $outcome remains distinct and state unchanged',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => outcome == 'cancelled'
              ? {'status': 'cancelled'}
              : {'status': 'error', 'code': outcome},
        );
        final ready = await transfer.prepareExport();
        final result = await transfer.writeExport(ready.token!);
        expect(
          result.status,
          outcome == 'cancelled'
              ? ZipTransferStatus.cancelled
              : ZipTransferStatus.error,
        );
        expect(state.snapshot, original);
      },
    );
    test('external read $outcome never saves', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => outcome == 'cancelled'
            ? {'status': 'cancelled'}
            : {'status': 'error', 'code': outcome},
      );
      final result = await transfer.readImport();
      expect(
        result.status,
        outcome == 'cancelled'
            ? ZipTransferStatus.cancelled
            : ZipTransferStatus.error,
      );
      expect(state.snapshot, original);
    });
  }

  for (final kind in ['zip', 'version', 'jpeg']) {
    test('invalid $kind rejects whole import', () async {
      if (kind == 'zip') input = Uint8List.fromList([0]);
      if (kind == 'version') {
        final plan = jsonBytes(zipPlanFixture());
        final manifest = zipManifest(plan)..['formatVersion'] = 2;
        input = testZip([
          TestZipEntry('manifest.json', jsonBytes(manifest)),
          TestZipEntry('plan.json', plan),
        ]);
      }
      if (kind == 'jpeg') {
        final plan = jsonBytes(zipPlanFixture());
        final photo = Uint8List.fromList([0]);
        input = testZip([
          TestZipEntry('manifest.json', jsonBytes(zipManifest(plan, photo))),
          TestZipEntry('plan.json', plan),
          TestZipEntry('photo.jpg', photo),
        ]);
      }
      final result = await transfer.readImport();
      expect(result.status, ZipTransferStatus.error);
      expect(result.codecIssue, switch (kind) {
        'zip' => ZipBackupIssue.invalidZip,
        'version' => ZipBackupIssue.unsupportedVersion,
        _ => ZipBackupIssue.invalidPhoto,
      });
      expect(result.token, null);
      expect(state.snapshot, original);
      expect(files.files.keys, [photoA]);
    });
  }

  for (final change in ['edit', 'reload', 'protection', 'recovery']) {
    test(
      'confirmation detects $change and releases shared operation',
      () async {
        final token = await candidate();
        final generation = state.generation;
        switch (change) {
          case 'edit':
            await state.saveCarName('newer');
          case 'reload':
            await state.load();
          case 'protection':
            state.unsupportedBackupVersion = 4;
          case 'recovery':
            state.phase = StartupPhase.recovered;
            state.acknowledgeRecovery();
        }
        expect(state.generation, greaterThan(generation));
        expect(
          (await transfer.confirmImport(token)).status,
          ZipTransferStatus.conflict,
        );
        expect(state.car!.name, isNot('ZIP restored'));
      },
    );
  }

  test(
    'explicit cancel consumes candidate, next operation invalidates old token',
    () async {
      final old = await candidate();
      expect(transfer.cancel().status, ZipTransferStatus.cancelled);
      final next = await candidate();
      expect(
        (await transfer.confirmImport(old)).status,
        ZipTransferStatus.conflict,
      );
      expect(
        (await transfer.confirmImport(next)).status,
        ZipTransferStatus.success,
      );
    },
  );

  test('foreign transfer token cannot replace its private candidate', () async {
    final otherState = PersistentPlanState(
      repository: TestRepository(Loaded(original)),
      referenceMonth: const YearMonth(2026, 10),
    );
    await otherState.load();
    final other = ZipBackupTransfer(state: otherState);
    final foreign = await other.readImport();
    final own = await candidate();
    expect(
      (await transfer.confirmImport(foreign.token!)).status,
      ZipTransferStatus.conflict,
    );
    expect(
      (await transfer.confirmImport(own)).status,
      ZipTransferStatus.success,
    );
    other.dispose();
    otherState.dispose();
  });

  for (final action in ['edit', 'reload', 'cancel', 'dispose']) {
    test('$action during photo preparation never applies import', () async {
      final token = await candidate();
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onWrite = () async {
        entered.complete();
        await release.future;
      };
      final restoring = transfer.confirmImport(token);
      await entered.future;
      switch (action) {
        case 'edit':
          await state.saveCarName('newer');
        case 'reload':
          await state.load();
        case 'cancel':
          transfer.cancel();
        case 'dispose':
          transfer.dispose();
      }
      release.complete();
      expect(
        (await restoring).status,
        action == 'edit' || action == 'reload'
            ? ZipTransferStatus.conflict
            : ZipTransferStatus.cancelled,
      );
      expect(state.car!.name, isNot('ZIP restored'));
      expect(state.photoId, photoA);
      expect(files.files.containsKey(photoA), true);
      expect(files.files.containsKey(photoB), false);
    });
  }

  test('photo preparation failure never reaches plan save', () async {
    files.onWrite = () async => throw const FileSystemException('injected');
    final token = await candidate();
    final before = memory.files[DataFile.current]!.toList();
    expect(
      (await transfer.confirmImport(token)).status,
      ZipTransferStatus.error,
    );
    expect(memory.files[DataFile.current], before);
    expect(state.snapshot, original);
  });

  for (final rollback in [false, true]) {
    test(
      'Safe Save failure rollback=$rollback preserves formal state and photos',
      () async {
        final token = await candidate();
        var fired = false;
        hooks.before = (op) {
          if (op == 'move.temp.current' && (!fired || rollback)) {
            fired = true;
            throw StateError('injected');
          }
        };
        final result = await transfer.confirmImport(token);
        expect(result.status, ZipTransferStatus.error);
        expect(result.saveFailure!.uncertain, rollback);
        expect(state.snapshot, original);
        expect(files.files.containsKey(photoA), true);
        if (rollback) {
          expect(state.phase, StartupPhase.uncertain);
          expect(files.files.containsKey(photoB), true);
          expect(await state.cleanupPhotos(), false);
          hooks.before = null;
          await state.load();
          expect(state.phase, StartupPhase.recovered);
          expect(state.photoId, photoA);
        } else {
          expect(memory.files[DataFile.current], bytes(original));
        }
      },
    );
  }

  test(
    'Saved only after verified current; session and photo adopted together',
    () async {
      final token = await candidate();
      final entered = Completer<void>();
      final release = Completer<void>();
      hooks.before = (op) async {
        if (op == 'move.temp.current') {
          entered.complete();
          await release.future;
        }
      };
      final restoring = transfer.confirmImport(token);
      await entered.future;
      expect(state.snapshot, original);
      expect(files.files.containsKey(photoB), true);
      expect(transfer.cancel().status, ZipTransferStatus.unavailable);
      expect(
        (await transfer.confirmImport(token)).status,
        ZipTransferStatus.conflict,
      );
      release.complete();
      expect((await restoring).status, ZipTransferStatus.success);
      expect(state.photoId, photoB);
      expect(state.car!.name, 'ZIP restored');
    },
  );

  test(
    'cleanup failure preserves successful import and both referenced photos',
    () async {
      files.onCleanup = () async => throw StateError('injected');
      expect(
        (await transfer.confirmImport(await candidate())).status,
        ZipTransferStatus.success,
      );
      expect(state.photoId, photoB);
      expect(files.files.keys, containsAll([photoA, photoB]));
    },
  );

  test('transfer disposal after save acceptance preserves successful import result', () async {
    final token = await candidate();
    final entered = Completer<void>();
    final release = Completer<void>();
    hooks.before = (op) async {
      if (op == 'move.temp.current') {
        entered.complete();
        await release.future;
      }
    };
    final saving = transfer.confirmImport(token);
    await entered.future;
    expect(state.snapshot, original);
    expect(files.files.containsKey(photoB), true);
    transfer.dispose(); // Keep State/Repository alive so the accepted save finishes.
    expect(
      (await transfer.confirmImport(token)).status,
      ZipTransferStatus.conflict,
    );
    release.complete();
    expect((await saving).status, ZipTransferStatus.success);
    hooks.before = null;
    expect(state.isDisposed, false);
    expect(state.phase, StartupPhase.ready);
    expect(state.car!.name, 'ZIP restored');
    expect(state.photoId, photoB);
    expect(state.session!.conditions, imported.planConditions);
    expect(
      state.session!.plannedExpenses.map((e) => e.id),
      imported.plannedExpenses.map((e) => e.id),
    );
    expect((await repository.load() as Loaded).data.photoId, photoB);
    expect(await photos.read(photoB), smallJpeg());
    expect(files.files.keys, containsAll([photoA, photoB]));
    expect(
      (await transfer.confirmImport(token)).status,
      ZipTransferStatus.conflict,
    );
    await state.load();
    expect(state.photoId, photoB);
    expect(state.car!.name, 'ZIP restored');
    await state.deletePhoto();
    await state.saveCarName('rotate past imported reference');
    expect(files.files, isEmpty); // Neither the old nor import lease leaked.
  });

  test('pending photo request cannot overwrite imported photo', () async {
    final request = state.beginPhotoChange();
    expect(
      (await transfer.confirmImport(await candidate())).status,
      ZipTransferStatus.success,
    );
    expect(await state.completePhotoChange(request, 'late'), false);
    expect(state.photoId, photoB);
  });

  test(
    'JSON and separate ZIP instances share gate through confirmation',
    () async {
      final token = await candidate();
      final json = BackupTransfer(state: state);
      final other = ZipBackupTransfer(state: state);
      expect((await json.export()).error, BackupTransferError.unavailable);
      expect(
        (await json.readCandidate()).error,
        BackupTransferError.unavailable,
      );
      expect(
        (await json.restore(BackupImportSuccess(imported))).error,
        BackupTransferError.unavailable,
      );
      expect(
        (await other.prepareExport()).status,
        ZipTransferStatus.unavailable,
      );
      expect((await other.readImport()).status, ZipTransferStatus.unavailable);
      expect(
        (await transfer.confirmImport(token)).status,
        ZipTransferStatus.success,
      );
      other.dispose();
    },
  );

  for (final decoding in [false, true]) {
    for (final disposing in [false, true]) {
      test(
        'late worker decoding=$decoding disposing=$disposing never advances',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          Future<void> pause() async {
            entered.complete();
            await release.future;
          }

          late Future<ZipTransferResult> running;
          if (decoding) {
            worker.beforeDecode = pause;
            running = transfer.readImport();
          } else {
            worker.beforeEncode = pause;
            running = transfer.writeExport(
              (await transfer.prepareExport()).token!,
            );
          }
          await entered.future;
          if (disposing) {
            transfer.dispose();
          } else {
            transfer.cancel();
          }
          final other = ZipBackupTransfer(state: state);
          expect(
            (await other.readImport()).status,
            ZipTransferStatus.unavailable,
          );
          release.complete();
          expect((await running).status, ZipTransferStatus.cancelled);
          expect(saves, 0);
          expect(state.snapshot, original);
          expect(
            (await other.readImport()).status,
            ZipTransferStatus.importConfirmation,
          );
          other.dispose();
        },
      );
    }
  }

  test('unexpected worker exception maps to error and releases gate', () async {
    worker.beforeEncode = () async => throw StateError('worker failed');
    expect(
      (await transfer.writeExport((await transfer.prepareExport()).token!))
          .error,
      ZipTransferError.unexpected,
    );
    expect(
      (await transfer.readImport()).status,
      ZipTransferStatus.importConfirmation,
    );
  });

  for (final afterPromotion in [false, true]) {
    test(
      'restart from interrupted filesystem image afterPromotion=$afterPromotion',
      () async {
        final token = await candidate();
        final captured = Completer<void>();
        final release = Completer<void>();
        final disk = MemoryStorage();
        final diskPhotos = ObservedPhotos();
        Future<void> pause(String op) async {
          if (op != 'move.temp.current') return;
          for (final entry in memory.files.entries) {
            disk.files[entry.key] = entry.value.toList();
          }
          for (final entry in files.files.entries) {
            diskPhotos.files[entry.key] = Uint8List.fromList(entry.value);
          }
          captured.complete();
          await release.future;
        }

        if (afterPromotion) {
          hooks.after = pause;
        } else {
          hooks.before = pause;
        }
        final saving = transfer.confirmImport(token);
        await captured.future;
        final restarted = PersistentPlanState(
          repository: KeepMyCarRepository(disk),
          referenceMonth: const YearMonth(2026, 10),
          photos: PhotoLibrary(storage: diskPhotos, processor: FakeProcessor()),
        );
        await restarted.load();
        expect(
          restarted.phase,
          afterPromotion ? StartupPhase.ready : StartupPhase.recovered,
        );
        expect(restarted.photoId, afterPromotion ? photoB : photoA);
        expect(await restarted.photos!.read(restarted.photoId!), smallJpeg());
        // Uncommitted JSON temp is never promoted by recovery.
        expect(
          restarted.car!.name,
          afterPromotion ? 'ZIP restored' : original.car.name,
        );
        restarted.dispose();
        release.complete();
        expect((await saving).status, ZipTransferStatus.success);
      },
    );
  }

  test('confirmation cancelled during picker ignores late bytes', () async {
    final selected = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => selected.future);
    final reading = transfer.readImport();
    transfer.cancel();
    expect(
      (await transfer.prepareExport()).status,
      ZipTransferStatus.unavailable,
    );
    selected.complete({'status': 'success', 'bytes': input});
    expect((await reading).status, ZipTransferStatus.cancelled);
    expect(state.snapshot, original);
    expect(
      (await transfer.prepareExport()).status,
      ZipTransferStatus.exportReady,
    );
  });

  test('state disposed during validation cannot return a candidate', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    worker.beforeDecode = () async {
      entered.complete();
      await release.future;
    };
    final reading = transfer.readImport();
    await entered.future;
    state.dispose();
    release.complete();
    expect((await reading).status, ZipTransferStatus.cancelled);
    // Existing tearDown owns a replacement notifier.
    transfer.dispose();
    state = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 10),
    );
    await state.load();
    transfer = ZipBackupTransfer(state: state);
  });

  test('photo omission token rejects same-phase state update', () async {
    files.files.clear();
    final ready = await transfer.prepareExport();
    await state.saveCarName('newer');
    expect(
      (await transfer.writeExport(
        ready.token!,
        approvePhotoOmission: true,
      )).status,
      ZipTransferStatus.conflict,
    );
    expect(saves, 0);
  });

  test('cleanup busy rejects start without consuming photo request', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onCleanup = () async {
      entered.complete();
      await release.future;
    };
    final cleaning = state.cleanupPhotos();
    await entered.future;
    expect(
      (await transfer.prepareExport()).status,
      ZipTransferStatus.unavailable,
    );
    expect((await transfer.readImport()).status, ZipTransferStatus.unavailable);
    release.complete();
    await cleaning;
    expect(
      (await transfer.prepareExport()).status,
      ZipTransferStatus.exportReady,
    );
  });

  test(
    'legacy JSON active operation blocks ZIP across different instances',
    () async {
      final selected = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (_) => selected.future);
      final json = BackupTransfer(state: state);
      final reading = json.readCandidate();
      expect(
        (await transfer.readImport()).status,
        ZipTransferStatus.unavailable,
      );
      expect(
        (await transfer.prepareExport()).status,
        ZipTransferStatus.unavailable,
      );
      selected.complete({'status': 'cancelled'});
      expect((await reading).status, BackupTransferStatus.cancelled);
      expect(
        (await transfer.prepareExport()).status,
        ZipTransferStatus.exportReady,
      );
    },
  );

  test(
    'future version discovered at save protects old JSON and new photo',
    () async {
      final token = await candidate();
      memory.files[DataFile.backup] = utf8.encode('{"formatVersion":4}');
      final before = memory.files[DataFile.current]!.toList();
      expect(
        (await transfer.confirmImport(token)).status,
        ZipTransferStatus.error,
      );
      expect(state.saveRestricted, true);
      expect(state.snapshot, original);
      expect(memory.files[DataFile.current], before);
      expect(files.files.keys, containsAll([photoA, photoB]));
    },
  );

  test('session preparation failure occurs before any JSON write', () async {
    transfer.dispose();
    state.dispose();
    state = PersistentPlanState(
      repository: repository,
      photos: photos,
      referenceMonth: const YearMonth(2026, 10),
      sessionFactory: (data, month) {
        if (data.car.name == 'ZIP restored') {
          throw StateError('session rejected');
        }
        return PlanSession(
          conditions: data.planConditions,
          birthMonth: data.ownerBirthMonth,
          referenceMonth: month,
          firstRegistrationMonth: data.car.firstRegistrationMonth,
          plannedExpenses: data.plannedExpenses,
        );
      },
    );
    await state.load();
    original = state.snapshot;
    transfer = ZipBackupTransfer(state: state);
    final token = await candidate();
    hooks.events.clear();
    expect(
      (await transfer.confirmImport(token)).status,
      ZipTransferStatus.error,
    );
    expect(
      hooks.events.any((e) => e.startsWith('write.') || e.startsWith('move.')),
      false,
    );
    expect(state.snapshot, original);
    expect(files.files.containsKey(photoA), true);
  });

  test('disabled funding values, nullable memo, IDs and original order survive import', () async {
    final p = imported.planConditions;
    final expenses = [
      const PlannedExpense(
        id: -2,
        name: 'past',
        plannedMonth: YearMonth(2020, 1),
        amountYen: 0,
        basis: ExpenseBasis.quoted,
        memo: null,
        status: PlannedExpenseStatus.completed,
      ),
      const PlannedExpense(
        id: 7,
        name: 'same month',
        plannedMonth: YearMonth(2020, 1),
        amountYen: 100,
        basis: ExpenseBasis.placeholder,
        memo: 'keep',
        status: PlannedExpenseStatus.planned,
      ),
    ];
    imported = (
      photoId: null,
      ownerBirthMonth: imported.ownerBirthMonth,
      car: imported.car,
      planConditions: PlanConditions(
        fundingPlanEnabled: false,
        currentMileageKm: p.currentMileageKm,
        annualMileageKm: p.annualMileageKm,
        ownershipTargetAge: p.ownershipTargetAge,
        currentCarFundYen: 123,
        reserveTargetAge: 20,
        largeRepairReserveYen: 456,
      ),
      plannedExpenses: expenses,
    );
    input = await codec.encode(imported);
    expect(
      (await transfer.confirmImport(await candidate())).status,
      ZipTransferStatus.success,
    );
    expect(state.session!.conditions, imported.planConditions);
    expect(state.session!.plannedExpenses.map((e) => e.id), [-2, 7]);
    expect(state.session!.plannedExpenses.map((e) => e.memo), [null, 'keep']);
    expect(state.photoId, null);
  });

  test('ZIP-wide size failure maps without external save', () async {
    worker.beforeEncode = () async =>
        throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
    final result = await transfer.writeExport(
      (await transfer.prepareExport()).token!,
    );
    expect(result.codecIssue, ZipBackupIssue.sizeLimit);
    expect(saves, 0);
    expect(state.snapshot, original);
  });

  for (final phase in [StartupPhase.noData, StartupPhase.failure]) {
    test('ZIP restores directly from $phase without initialization', () async {
      memory.files.clear();
      if (phase == StartupPhase.failure) memory.files[DataFile.current] = [42];
      await state.load();
      expect(state.phase, phase);
      final read = await transfer.readImport();
      expect(read.status, ZipTransferStatus.importConfirmation);
      expect(
        (await transfer.confirmImport(read.token!)).status,
        ZipTransferStatus.success,
      );
      expect(state.phase, StartupPhase.ready);
      expect(state.photoId, photoB);
      expect(state.car!.name, 'ZIP restored');
    });
  }

  test(
    'future backup permits readable-current export but rejects import',
    () async {
      memory.files[DataFile.backup] = utf8.encode('{"formatVersion":4}');
      await state.load();
      final ready = await transfer.prepareExport();
      expect(ready.status, ZipTransferStatus.exportReady);
      await state.cleanupPhotos();
      expect(
        (await transfer.writeExport(ready.token!)).status,
        ZipTransferStatus.success,
      );
      expect(
        (await transfer.readImport()).status,
        ZipTransferStatus.unavailable,
      );
    },
  );

  test('state becomes uncertain during encode: no external write', () async {
    worker.beforeEncode = () async {
      state.phase = StartupPhase.uncertain;
    };
    final ready = await transfer.prepareExport();
    expect(
      (await transfer.writeExport(ready.token!)).status,
      ZipTransferStatus.unavailable,
    );
    expect(saves, 0);
  });

  test(
    'state disposal after save acceptance retains committed candidate photo',
    () async {
      final token = await candidate();
      final entered = Completer<void>();
      final release = Completer<void>();
      hooks.before = (op) async {
        if (op == 'move.temp.current') {
          entered.complete();
          await release.future;
        }
      };
      final saving = transfer.confirmImport(token);
      await entered.future;
      state.dispose();
      release.complete();
      expect((await saving).status, ZipTransferStatus.error);
      final saved = await repository.load() as Loaded;
      expect(saved.data.photoId, photoB);
      expect(files.files.keys, containsAll([photoA, photoB]));
      transfer.dispose();
      state = PersistentPlanState(
        repository: repository,
        photos: photos,
        referenceMonth: const YearMonth(2026, 10),
      );
      await state.load();
      expect(state.photoId, photoB);
      transfer = ZipBackupTransfer(state: state);
    },
  );
}
