import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import '../persistence/keep_my_car_repository_test.dart'
    show HookStorage, bytes;
import '../persistence_app_support.dart';
import '../step15_e1_test.dart' show MemoryStorage;
import 'photo_test_support.dart';

RestoredCarData withId(RestoredCarData data, String? id) => (
  photoId: id,
  ownerBirthMonth: data.ownerBirthMonth,
  car: data.car,
  planConditions: data.planConditions,
  plannedExpenses: data.plannedExpenses,
);

void main() {
  late MemoryStorage memory;
  late HookStorage hooks;
  late KeepMyCarRepository repository;
  late FakeProcessor processor;
  late MemoryPhotos files;
  late PhotoLibrary library;
  late PersistentPlanState state;
  setUp(() async {
    memory = MemoryStorage()
      ..files[DataFile.current] = bytes(withId(sampleSnapshot(), photoA));
    hooks = HookStorage(memory);
    repository = KeepMyCarRepository(hooks);
    processor = FakeProcessor();
    files = MemoryPhotos()..files[photoA] = smallJpeg();
    var sequence = 0;
    library = PhotoLibrary(
      storage: files,
      processor: processor,
      newId: () => [photoB, photoC, photoD][sequence++],
    );
    state = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 9),
      photos: library,
    );
    await state.load();
  });
  tearDown(() {
    state.dispose();
  });

  test(
    'replacement, deletion and reload retain backup photo until rotation',
    () async {
      final session = state.session;
      final conditions = state.session!.conditions;
      final expenses = state.session!.plannedExpenses;
      final result = state.session!.reserveResult;
      expect(await state.changePhoto('source'), true);
      expect(state.photoId, photoB);
      expect(state.session, same(session));
      expect(state.session!.conditions, same(conditions));
      expect(state.session!.plannedExpenses, same(expenses));
      expect(state.session!.reserveResult, same(result));
      expect(files.files.keys, containsAll([photoA, photoB]));
      await state.load();
      expect(state.photoId, photoB);
      await state.deletePhoto();
      expect(state.photoId, null);
      expect(files.files.keys, [photoB]);
      await state.saveCarName('rotate backup');
      expect(files.files, isEmpty);
      await state.load();
      expect(state.photoId, null);
    },
  );

  test('photo remains formal old value until Saved', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    hooks.before = (op) async {
      if (op == 'move.temp.current') {
        entered.complete();
        await release.future;
      }
    };
    final change = state.changePhoto('source');
    await entered.future;
    expect(state.photoId, photoA);
    expect(files.files.keys, containsAll([photoA, photoB]));
    expect(await state.cleanupPhotos(), false);
    await expectLater(
      state.saveExpense(
        name: 'blocked',
        month: const YearMonth(2028, 1),
        amountYen: 0,
      ),
      throwsA(isA<SaveRequestFailure>()),
    );
    release.complete();
    expect(await change, true);
    expect(state.photoId, photoB);
  });

  test('ordinary expense edits during conversion are retained', () async {
    final converted = Completer<void>();
    processor.onProcess = (_, cancel) async {
      await converted.future;
      return smallJpeg();
    };
    final oldCount = state.session!.plannedExpenses.length;
    final change = state.changePhoto('source');
    await state.saveExpense(
      name: 'during photo',
      month: const YearMonth(2028, 1),
      amountYen: 0,
    );
    final newId = state.session!.plannedExpenses.last.id;
    converted.complete();
    expect(await change, true);
    expect(state.session!.plannedExpenses.length, oldCount + 1);
    expect(state.session!.plannedExpenses.last.id, newId);
    await state.load();
    expect(state.session!.plannedExpenses.last.name, 'during photo');
    expect(state.photoId, photoB);
  });

  test('finished conversion waits for in-flight normal Safe Save', () async {
    final converted = Completer<void>();
    final entered = Completer<void>();
    final release = Completer<void>();
    processor.onProcess = (_, cancel) async {
      await converted.future;
      return smallJpeg();
    };
    final change = state.changePhoto('source');
    var first = true;
    hooks.before = (op) async {
      if (first && op == 'write.temp') {
        first = false;
        entered.complete();
        await release.future;
      }
    };
    final edit = Future.sync(() => state.saveCarName('latest name'));
    await entered.future;
    converted.complete();
    await Future<void>.delayed(Duration.zero);
    expect(state.photoId, photoA);
    release.complete();
    await edit;
    expect(await change, true);
    expect(state.car!.name, 'latest name');
  });

  for (final action in ['import', 'reload', 'delete', 'cancel']) {
    test('$action invalidates pending photo request', () async {
      final converted = Completer<void>();
      processor.onProcess = (_, cancel) async {
        await converted.future;
        return smallJpeg();
      };
      final change = state.changePhoto('source');
      switch (action) {
        case 'import':
          await state.restoreFromBackup(BackupImportSuccess(sampleSnapshot()));
        case 'reload':
          await state.load();
        case 'delete':
          await state.deletePhoto();
        case 'cancel':
          state.cancelPhotoChange();
      }
      converted.complete();
      expect(await change, false);
      expect(
        state.photoId,
        action == 'import' || action == 'delete' ? null : photoA,
      );
      expect(files.files.containsKey(photoB), false);
    });
  }

  test('reselection completion reversal never adopts old result', () async {
    final first = Completer<void>();
    processor.onProcess = (path, cancel) async {
      if (path == 'first') await first.future;
      return smallJpeg();
    };
    final old = state.changePhoto('first');
    expect(await state.changePhoto('second'), true);
    expect(state.photoId, photoC);
    first.complete();
    expect(await old, false);
    expect(state.photoId, photoC);
    expect(files.files.containsKey(photoB), false);
  });

  test(
    'new photo request waits behind an already accepted photo save',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var first = true;
      hooks.before = (op) async {
        if (first && op == 'move.temp.current') {
          first = false;
          entered.complete();
          await release.future;
        }
      };
      final old = state.changePhoto('first');
      await entered.future;
      final newer = state.changePhoto('second');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      expect(await old, true);
      expect(await newer, true);
      expect(state.photoId, photoC);
      expect((await repository.load() as Loaded).data.photoId, photoC);
      expect(files.files.keys, containsAll([photoB, photoC]));
    },
  );

  test('read failure during reference inspection prevents cleanup', () async {
    files.files[photoC] = smallJpeg();
    hooks.before = (op) {
      if (op == 'read.backup') throw StateError('read denied');
    };
    expect(await state.cleanupPhotos(), false);
    expect(files.files.containsKey(photoC), true);
    expect(files.sweeps, isEmpty);
  });

  test(
    'future version discovered during photo save protects JSON and all photos',
    () async {
      final converted = Completer<void>();
      processor.onProcess = (_, cancel) async {
        await converted.future;
        return smallJpeg();
      };
      final change = state.changePhoto('source');
      memory.files[DataFile.backup] = utf8.encode('{"formatVersion":4}');
      final before = memory.files[DataFile.current]!.toList();
      converted.complete();
      await expectLater(change, throwsA(isA<SaveRequestFailure>()));
      expect(state.saveRestricted, true);
      expect(state.photoId, photoA);
      expect(memory.files[DataFile.current], before);
      expect(files.files.keys, containsAll([photoA, photoB]));
    },
  );

  test('rollback uncertainty clears only after reload; both references remain protected', () async {
    var fired = false;
    hooks.before = (op) {
      if (op == 'move.temp.current') {
        fired = true;
        throw StateError('promotion and rollback');
      }
    };
    await expectLater(
      state.changePhoto('source'),
      throwsA(isA<SaveRequestFailure>()),
    );
    expect(fired, true);
    expect(state.phase, StartupPhase.uncertain);
    hooks.before = null;
    await state.load();
    expect(state.phase, StartupPhase.recovered);
    expect(state.photoId, photoA);
    // Missing current is known; backup has been fully inspected. Orphan B can
    // now be removed, but A remains recoverable from backup.
    expect(await state.cleanupPhotos(), true);
    expect(files.files.keys, [photoA]);
  });

  test('picker request is one-shot and invalidated before a late selection returns', () async {
    final pending = state.beginPhotoChange();
    await state.load();
    expect(await state.completePhotoChange(pending, 'late'), false);
    expect(processor.paths, isEmpty);
    final current = state.beginPhotoChange();
    expect(await state.completePhotoChange(current, 'first'), true);
    expect(await state.completePhotoChange(current, 'replay'), false);
    expect(processor.paths, ['first']);
  });

  for (final failure in ['photo', 'temp', 'promotion', 'rollback']) {
    test(
      '$failure failure protects formal state and rollback references',
      () async {
        final old = state.snapshot;
        final before = memory.files[DataFile.current]!.toList();
        if (failure == 'photo') {
          files.onWrite = () async => throw StateError('photo write');
        }
        if (failure == 'temp') {
          hooks.before = (op) {
            if (op == 'write.temp') throw StateError('temp write');
          };
        }
        if (failure == 'promotion' || failure == 'rollback') {
          var fired = false;
          hooks.before = (op) {
            if (op == 'move.temp.current' &&
                (!fired || failure == 'rollback')) {
              fired = true;
              throw StateError('promotion/rollback');
            }
          };
        }
        await expectLater(state.changePhoto('source'), throwsA(anything));
        expect(state.snapshot, old);
        expect(files.files.containsKey(photoA), true);
        if (failure == 'rollback') {
          expect(state.phase, StartupPhase.uncertain);
          expect(files.files.containsKey(photoB), true);
          expect(await state.cleanupPhotos(), false);
          expect(
            await repository.withPhotoReferencesForCleanup(
              (_) async => fail('uncertain cleanup'),
            ),
            false,
          );
        } else {
          expect(memory.files[DataFile.current], before);
        }
      },
    );
  }

  test('delete JSON failure leaves old reference and photo', () async {
    hooks.before = (op) {
      if (op == 'write.temp') throw StateError('write');
    };
    await expectLater(state.deletePhoto(), throwsA(isA<SaveRequestFailure>()));
    expect(state.photoId, photoA);
    expect(files.files.containsKey(photoA), true);
  });

  test('Saved after dispose retains persisted candidate and photos', () async {
    final repo = TestRepository(Loaded(withId(sampleSnapshot(), photoA)));
    final pending = Completer<SaveResult>();
    repo.onSave = (_) => pending.future;
    final disposable = PersistentPlanState(
      repository: repo,
      referenceMonth: const YearMonth(2026, 9),
      photos: library,
    );
    await disposable.load();
    final change = disposable.changePhoto('source');
    while (repo.saves.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    disposable.dispose();
    final failure = expectLater(change, throwsA(isA<SaveRequestFailure>()));
    pending.complete(const Saved());
    await failure;
    expect((repo.result as Loaded).data.photoId, photoB);
    expect(files.files.keys, containsAll([photoA, photoB]));
  });

  test('cleanup errors do not reverse successful photo save', () async {
    files.onCleanup = () async => throw StateError('delete failed');
    expect(await state.changePhoto('source'), true);
    expect(state.photoId, photoB);
    expect((await repository.load() as Loaded).data.photoId, photoB);
  });

  for (final file in [DataFile.current, DataFile.backup]) {
    for (final bad in ['corrupt', 'future']) {
      test('$bad ${file.name} prevents all cleanup', () async {
        files.files[photoC] = smallJpeg();
        memory.files[file] = utf8.encode(
          bad == 'corrupt' ? '{broken' : '{"formatVersion":4}',
        );
        expect(await state.cleanupPhotos(), false);
        expect(files.files.containsKey(photoC), true);
        expect(files.sweeps, isEmpty);
      });
    }
  }

  test('missing/corrupt photo permits plan load and backup recovery', () async {
    files.files.clear();
    await state.load();
    expect(state.phase, StartupPhase.ready);
    expect(await library.read(photoA), null);
    memory.files[DataFile.backup] = memory.files[DataFile.current]!;
    memory.files[DataFile.current] = [42];
    files.files[photoA] = corruptJpegScan();
    await state.load();
    expect(state.phase, StartupPhase.recovered);
    expect(state.photoId, photoA);
    expect(state.session, isNotNull);
    expect(await library.read(photoA), null);
    expect(await state.cleanupPhotos(), false);
  });

  test(
    'cleanup holds repository and app guards and protects export lease',
    () async {
      files.files[photoC] = smallJpeg();
      final exportLease = library.protect(photoC);
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onCleanup = () async {
        entered.complete();
        await release.future;
      };
      final cleanup = state.cleanupPhotos();
      await entered.future;
      await expectLater(
        Future.sync(() => state.saveCarName('blocked')),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(
        (await repository.save(sampleSnapshot()) as SaveFailure).issue.stage,
        PersistenceStage.busy,
      );
      expect(
        (await repository.load() as LoadFailure).issues.single.stage,
        PersistenceStage.busy,
      );
      expect(() => library.protect(photoD), throwsA(isA<PhotoFailure>()));
      release.complete();
      expect(await cleanup, true);
      expect(files.files.containsKey(photoC), true);
      exportLease.release();
      files.onCleanup = null;
      expect(await state.cleanupPhotos(), true);
      expect(files.files.containsKey(photoC), false);
    },
  );

  test('in-flight preparation is protected from cleanup', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onWrite = () async {
      entered.complete();
      await release.future;
    };
    final change = state.changePhoto('source');
    await entered.future;
    var readFinished = false;
    final reading = library.read(photoB).then((value) {
      readFinished = true;
      return value;
    });
    expect(await state.cleanupPhotos(), true);
    expect(readFinished, false);
    expect(files.sweeps.last, contains(photoB));
    release.complete();
    expect(await change, true);
    expect(await reading, isNotNull);
  });

  test('returning photo selection waits for cleanup without consuming a failed request', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onCleanup = () async {
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final cleaning = state.cleanupPhotos();
    await entered.future;
    final request = state.beginPhotoChange();
    final change = state.completePhotoChange(request, 'selected');
    expect(await state.completePhotoChange(request, 'duplicate'), false);
    expect(processor.paths, isEmpty);
    release.complete();
    expect(await cleaning, true);
    expect(await change, true);
    expect(processor.paths, ['selected']);
    expect(state.photoId, photoB);
  });

  for (final action in ['cancel', 'reselect', 'dispose', 'version']) {
    test('photo waiting for cleanup rechecks $action', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onCleanup = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final cleaning = state.cleanupPhotos();
      await entered.future;
      final old = state.changePhoto('old');
      Future<bool>? newer;
      final disposable = action == 'dispose';
      switch (action) {
        case 'cancel':
          state.cancelPhotoChange();
        case 'reselect':
          newer = state.changePhoto('new');
        case 'dispose':
          state.dispose();
        case 'version':
          state.unsupportedBackupVersion = 4;
      }
      if (action != 'version') {
        expect(await old, false); // cancellation wakes before release
      }
      release.complete();
      expect(await cleaning, true);
      if (action == 'version') expect(await old, false);
      if (newer != null) {
        expect(await newer, true);
        expect(processor.paths, ['new']);
      } else {
        expect(processor.paths, isEmpty);
      }
      if (disposable) {
        // The shared tearDown disposes state, so use a fresh unused instance.
        state = PersistentPlanState(
          repository: repository,
          referenceMonth: const YearMonth(2026, 9),
        );
      }
    });
  }

  test(
    'photo request also waits for cleanup acquired directly on the library',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onCleanup = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final cleaning = library.cleanup({photoA});
      await entered.future;
      final change = state.changePhoto('selected');
      release.complete();
      await cleaning;
      expect(await change, true);
      expect(state.photoId, photoB);
    },
  );

  test(
    'cancellation wakes a photo request waiting for the library lease',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onCleanup = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final cleaning = library.cleanup({photoA});
      await entered.future;
      final change = state.changePhoto('cancelled');
      state.cancelPhotoChange();
      expect(await change, false);
      expect(processor.paths, isEmpty);
      release.complete();
      await cleaning;
    },
  );

  test('cleanup rejection is temporary; gate release notifies Import/Export availability', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final availability = <(bool, bool)>[];
    state.addListener(
      () => availability.add((state.canRestoreBackup, state.canExportBackup)),
    );
    files.onCleanup = () async {
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final before = state.snapshot;
    final cleaning = state.cleanupPhotos();
    await entered.future;
    expect(state.canRestoreBackup, false);
    expect(state.canExportBackup, false);
    expect(availability.first, (false, false));
    await expectLater(
      state.saveCarName('rejected'),
      throwsA(isA<SaveRequestFailure>()),
    );
    await expectLater(
      state.restoreFromBackup(BackupImportSuccess(sampleSnapshot())),
      throwsA(isA<SaveRequestFailure>()),
    );
    expect(state.snapshot, before);
    release.complete();
    expect(await cleaning, true);
    expect(availability.last, (true, true));
    files.onCleanup = null;
    await state.saveCarName('after cleanup');
    expect(state.car!.name, 'after cleanup');
    expect(state.canRestoreBackup, true);
    expect(state.canExportBackup, true);
  });

  test(
    'Saved state survives cleanup busy and release refreshes availability',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final availability = <(bool, bool)>[];
      state.addListener(
        () => availability.add((state.canRestoreBackup, state.canExportBackup)),
      );
      files.onCleanup = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final saving = state.saveCarName('Saved before cleanup');
      await entered.future;
      expect(state.car!.name, 'Saved before cleanup');
      expect(availability.last, (false, false));
      await expectLater(
        state.saveCarName('rejected'),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(state.car!.name, 'Saved before cleanup');
      release.complete();
      await saving;
      expect(availability.last, (true, true));
      final loaded = await repository.load();
      expect(loaded, isA<Loaded>());
      expect((loaded as Loaded).data.car.name, 'Saved before cleanup');
    },
  );
}
