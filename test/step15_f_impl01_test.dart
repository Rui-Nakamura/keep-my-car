import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/plan_conditions_validation.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_dto.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_json_codec.dart';
import 'package:keep_my_car/persistence/keep_my_car_payload_codec.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'backup/fixtures/backup_v1_fixture.dart';
import 'persistence/fixtures/persistence_v3_fixture.dart';
import 'persistence/keep_my_car_persistence_test.dart' show wire;
import 'persistence/keep_my_car_repository_test.dart' show HookStorage;
import 'persistence_app_support.dart';
import 'plan_test_support.dart';
import 'step15_e1_test.dart' show MemoryStorage, v2, toggle;

const codec = KeepMyCarJsonCodec();
const mapper = KeepMyCarDataMapper();
const backup = BackupV1Codec();
const reference = YearMonth(2026, 9);

Map<String, dynamic> v3() =>
    jsonDecode(persistenceV3Fixture) as Map<String, dynamic>;
List<int> bytes(Object root) => utf8.encode(jsonEncode(root));
RestoredCarData domain(Map<String, dynamic> root) =>
    mapper.toDomain(codec.decode(jsonEncode(root)));
RestoredCarData withPhoto(RestoredCarData data, String? photoId) => (
  photoId: photoId,
  ownerBirthMonth: data.ownerBirthMonth,
  car: data.car,
  planConditions: data.planConditions,
  plannedExpenses: data.plannedExpenses,
);

void main() {
  for (final version in [1, 2, 3]) {
    for (final photo in [null, photoIdV3]) {
      test('direct v$version DTO photo=$photo enforces its storage schema', () {
        final source = codec.decode(persistenceV3Fixture);
        final dto = KeepMyCarDataDto(
          formatVersion: version,
          photoId: photo,
          ownerBirthMonth: source.ownerBirthMonth,
          car: source.car,
          planConditions: source.planConditions,
          plannedExpenses: source.plannedExpenses,
        );
        if (version < 3 && photo != null) {
          expect(() => codec.encode(dto), throwsFormatException);
          expect(
            () => const KeepMyCarPayloadCodec().encode(dto),
            throwsFormatException,
          );
          expect(() => mapper.toDomain(dto), throwsFormatException);
        } else {
          final restored = mapper.toDomain(codec.decode(codec.encode(dto)));
          expect(restored.photoId, photo);
          expect(restored.planConditions, domain(v3()).planConditions);
        }
      });
    }
  }
  for (final photo in [
    null,
    photoIdV3,
    '00000000-0000-4000-b000-000000000000',
  ]) {
    test(
      'v3 independent fixture and formal encode round trip photo=$photo',
      () {
        final root = v3()..['photoId'] = photo;
        final data = domain(root);
        final dto = mapper.toDto(
          photoId: data.photoId,
          ownerBirthMonth: data.ownerBirthMonth,
          car: data.car,
          planConditions: data.planConditions,
          plannedExpenses: data.plannedExpenses,
        );
        expect(dto.formatVersion, 3);
        expect(jsonDecode(codec.encode(dto)), root);
        expect(mapper.toDomain(codec.decode(codec.encode(dto))).photoId, photo);
        expect(data.planConditions.fundingPlanEnabled, true);
      },
    );
  }
  test('v3 missing photoId fails both structural codecs', () {
    final root = v3()..remove('photoId');
    expect(() => codec.decode(jsonEncode(root)), throwsFormatException);
    expect(
      () => const KeepMyCarPayloadCodec().decode(root, version: 3),
      throwsFormatException,
    );
  });
  for (final invalid in <Object>[
    '',
    photoIdV3.toUpperCase(),
    photoIdV3.replaceAll('-', ''),
    '$photoIdV3\n',
    '$photoIdV3 ',
    ' $photoIdV3',
    '550e8400-e29b-11d4-a716-446655440000',
    '550e8400-e29b-51d4-a716-446655440000',
    '550e8400-e29b-41d4-7716-446655440000',
    '550e8400-e29b-41d4-c716-446655440000',
    'g50e8400-e29b-41d4-a716-446655440000',
    'photo.jpg',
    'C:\\photos\\photo.jpg',
    '/photos/photo.jpg',
    1,
    true,
    <Object>[],
    <String, Object>{},
  ]) {
    test(
      'v3 rejects photoId ${jsonEncode(invalid)} at schema boundaries',
      () async {
        expect(
          () => codec.decode(jsonEncode(v3()..['photoId'] = invalid)),
          throwsFormatException,
        );
        if (invalid is! String) return;
        final source = codec.decode(persistenceV3Fixture);
        final invalidDto = KeepMyCarDataDto(
          photoId: invalid,
          ownerBirthMonth: source.ownerBirthMonth,
          car: source.car,
          planConditions: source.planConditions,
          plannedExpenses: source.plannedExpenses,
        );
        expect(() => codec.encode(invalidDto), throwsFormatException);
        expect(
          () => const KeepMyCarPayloadCodec().encode(invalidDto),
          throwsFormatException,
        );
        expect(() => mapper.toDomain(invalidDto), throwsFormatException);
        final data = mapper.toDomain(source);
        expect(
          () => mapper.toDto(
            photoId: invalid,
            ownerBirthMonth: data.ownerBirthMonth,
            car: data.car,
            planConditions: data.planConditions,
            plannedExpenses: data.plannedExpenses,
          ),
          throwsFormatException,
        );
        final storage = MemoryStorage()..files[DataFile.current] = bytes(v3());
        final before = Map<DataFile, List<int>>.from(storage.files);
        final failed = await KeepMyCarRepository(
          storage,
        ).save(withPhoto(data, invalid)) as SaveFailure;
        expect(failed.issue.stage, PersistenceStage.encode);
        expect(storage.mutations, isEmpty);
        expect(storage.files, before);
      },
    );
  }
  for (final value in <Object?>['missing', null, 'true', 1, 1.0, [], {}]) {
    test('v3 rejects fundingPlanEnabled=$value', () {
      final root = v3();
      if (value == 'missing') {
        root['planConditions'].remove('fundingPlanEnabled');
      } else {
        root['planConditions']['fundingPlanEnabled'] = value;
      }
      expect(() => codec.decode(jsonEncode(root)), throwsFormatException);
    });
  }
  for (final version in [1, 2]) {
    test(
      'v$version read preserves bytes; explicit save migrates to v3',
      () async {
        final root = version == 1 ? wire() : v2(enabled: false);
        root['photoId'] = 'unvalidated legacy unknown field';
        final original = utf8.encode(' \n${jsonEncode(root)}\n');
        final storage = MemoryStorage()..files[DataFile.current] = original;
        final repo = KeepMyCarRepository(storage);
        final loaded = (await repo.load() as Loaded).data;
        expect(loaded.photoId, isNull);
        expect(loaded.planConditions.fundingPlanEnabled, version == 1);
        expect(storage.files[DataFile.current], original);
        expect(storage.mutations, isEmpty);
        expect(await repo.save(loaded), isA<Saved>());
        final saved = jsonDecode(utf8.decode(storage.files[DataFile.current]!));
        expect(saved['formatVersion'], 3);
        expect(saved.containsKey('photoId'), true);
        expect(saved['photoId'], isNull);
        expect(saved['planConditions']['fundingPlanEnabled'], version == 1);
        expect(storage.files[DataFile.backup], original);
      },
    );
  }
  test('v3 keeps v2 validation; legacy relation is v1-only', () {
    for (final root in [v2(), v3()]) {
      root['planConditions']['reserveTargetAge'] = 100;
      expect(domain(root).planConditions.reserveTargetAge, 100);
    }
    final legacy = wire();
    legacy['planConditions']['reserveTargetAge'] = 100;
    expect(() => domain(legacy), throwsArgumentError);
  });
  for (final current in [1, 2, 3, 0]) {
    for (final previous in [1, 2, 3]) {
      test(
        'mixed recovery current=$current backup=$previous is read only',
        () async {
          Map<String, dynamic> root(int version) => switch (version) {
            1 => wire(),
            2 => v2(),
            _ => v3(),
          };
          final currentRoot = root(current);
          currentRoot['car']['name'] = 'current';
          final backupRoot = root(previous);
          backupRoot['car']['name'] = 'backup';
          final storage = MemoryStorage()
            ..files[DataFile.current] = current == 0 ? [42] : bytes(currentRoot)
            ..files[DataFile.backup] = bytes(backupRoot)
            ..files[DataFile.temp] = bytes(v3());
          final before = Map<DataFile, List<int>>.from(storage.files);
          final result = await KeepMyCarRepository(storage).load();
          final data = current == 0
              ? (result as Recovered).data
              : (result as Loaded).data;
          expect(data.car.name, current == 0 ? 'backup' : 'current');
          expect(
            data.photoId,
            (current == 0 ? previous : current) == 3 ? photoIdV3 : null,
          );
          expect(storage.mutations, isEmpty);
          expect(storage.files, before);
        },
      );
    }
  }
  for (final future in [4, 999]) {
    for (final file in [DataFile.current, DataFile.backup]) {
      test(
        'internal future v$future at ${file.name} protects all bytes',
        () async {
          final storage = MemoryStorage()
            ..files[DataFile.current] = bytes(v2())
            ..files[DataFile.backup] = bytes(v3());
          storage.files[file] = bytes({'formatVersion': future});
          final before = Map<DataFile, List<int>>.from(storage.files);
          final repo = KeepMyCarRepository(storage);
          final loaded = await repo.load();
          if (file == DataFile.current) {
            expect((loaded as VersionProtected).version, future);
          } else {
            expect((loaded as Loaded).unsupportedBackupVersion, future);
          }
          expect(await repo.save(domain(v3())), isA<SaveFailure>());
          expect(storage.mutations, isEmpty);
          expect(storage.files, before);
        },
      );
    }
  }
  for (final oldVersion in [1, 2, 3]) {
    for (final failure in ['temp', 'current', 'rollback', 'success']) {
      test(
        'photo safe save old v$oldVersion $failure preserves exact rollback bytes',
        () async {
          final oldRoot = switch (oldVersion) {
            1 => wire(),
            2 => v2(),
            _ => v3(),
          };
          final oldCurrent = utf8.encode(' \n${jsonEncode(oldRoot)}\n');
          final oldBackup = utf8.encode(' ${jsonEncode(v2(enabled: false))}\n');
          final memory = MemoryStorage()
            ..files[DataFile.current] = oldCurrent
            ..files[DataFile.backup] = oldBackup;
          final storage = HookStorage(memory);
          var tampered = false;
          storage.after = (op) {
            if (!tampered &&
                ((failure == 'temp' && op == 'write.temp') ||
                    ((failure == 'current' || failure == 'rollback') &&
                        op == 'move.temp.current'))) {
              tampered = true;
              final bad = v3()..remove('photoId');
              memory.files[failure == 'temp'
                  ? DataFile.temp
                  : DataFile.current] = bytes(
                bad,
              );
            }
          };
          storage.before = (op) {
            if (failure == 'rollback' && tampered && op == 'write.temp') {
              throw StateError('rollback write failure');
            }
          };
          const nextPhoto = '550e8400-e29b-41d4-a716-446655440001';
          final result = await KeepMyCarRepository(storage)
              .save(withPhoto(domain(v3()), nextPhoto));
          if (failure == 'success') {
            expect(result, isA<Saved>());
            expect(
              domain(jsonDecode(utf8.decode(memory.files[DataFile.current]!)))
                  .photoId,
              nextPhoto,
            );
            expect(memory.files[DataFile.backup], oldCurrent);
          } else {
            final failed = result as SaveFailure;
            expect(
              failed.issue.stage,
              failure == 'temp'
                  ? PersistenceStage.verifyTemp
                  : PersistenceStage.verifyCurrent,
            );
            expect(
              failed.rollbackIssues,
              failure == 'rollback' ? isNotEmpty : isEmpty,
            );
            if (failure != 'rollback') {
              expect(memory.files[DataFile.current], oldCurrent);
              expect(memory.files[DataFile.backup], oldBackup);
            } else {
              expect(memory.files[DataFile.backup], oldCurrent);
            }
          }
        },
      );
    }
  }

  final actions = <String, Future<dynamic> Function(PersistentPlanState)>{
    'car name': (s) async => await s.saveCarName('変更した愛車'),
    'basic mileage': (s) async =>
        await s.applyBasic(conditions(mileage: 46000, annual: 5000)),
    'ownership target': (s) async =>
        await s.applyBasic(conditions(ownership: 75)),
    'funding start': (s) async => await s.applyFunding(conditions()),
    'funding restart': (s) async =>
        await s.applyFunding(conditions(fund: 700000)),
    'funding update': (s) async =>
        await s.applyFunding(conditions(fund: 800000)),
    'funding stop': (s) async =>
        await s.applyFunding(toggle(s.session!.conditions, false)),
    'apply API': (s) async => await s.apply(conditions(annual: 6000)),
    'expense add zero yen': (s) => s.saveExpense(
      name: '追加',
      month: const YearMonth(2028, 1),
      amountYen: 0,
    ),
    'expense edit': (s) => s.saveExpense(
      id: 1,
      name: '編集',
      month: const YearMonth(2028, 1),
      amountYen: 90000,
    ),
    'expense delete': (s) => s.deleteExpense(1),
  };
  for (final action in actions.entries) {
    for (final outcome in ['saved', 'failed', 'uncertain']) {
      test(
        '${action.key} $outcome carries photo in candidate and formal snapshot',
        () async {
          final root = v3();
          if (action.key == 'funding start' ||
              action.key == 'funding restart') {
            root['planConditions']['fundingPlanEnabled'] = false;
          }
          final repo = TestRepository(Loaded(domain(root)));
          final state = PersistentPlanState(
            repository: repo,
            referenceMonth: reference,
          );
          addTearDown(state.dispose);
          await state.load();
          final original = state.snapshot;
          final pending = Completer<SaveResult>();
          repo.onSave = (_) => pending.future;
          final request = action.value(state);
          expect(repo.saves.single.photoId, photoIdV3);
          expect(state.photoId, photoIdV3);
          expect(state.snapshot.planConditions, original.planConditions);
          expect(state.snapshot.car, same(original.car));
          if (outcome == 'saved') {
            pending.complete(const Saved());
            await request;
            expect(
              state.snapshot.planConditions,
              repo.saves.single.planConditions,
            );
            expect(
              state.snapshot.plannedExpenses,
              repo.saves.single.plannedExpenses,
            );
          } else {
            final rejected = expectLater(
              request,
              throwsA(
                isA<SaveRequestFailure>().having(
                  (e) => e.uncertain,
                  'uncertain',
                  outcome == 'uncertain',
                ),
              ),
            );
            pending.complete(saveFailure(uncertain: outcome == 'uncertain'));
            await rejected;
            expect(state.snapshot, original);
            expect(
              state.phase,
              outcome == 'uncertain'
                  ? StartupPhase.uncertain
                  : StartupPhase.ready,
            );
          }
          expect(state.snapshot.photoId, photoIdV3);
        },
      );
    }
  }
  for (final version in [1, 2]) {
    for (final outcome in ['saved', 'failed', 'uncertain']) {
      test(
        'external v$version import $outcome resets photo only after Saved',
        () async {
          final envelope = jsonDecode(backupV1Fixture);
          envelope['exportFormatVersion'] = version;
          if (version == 2) {
            envelope['data']['planConditions']['fundingPlanEnabled'] = false;
          }
          envelope['data']['photoId'] = photoIdV3;
          final imported =
              backup.decode(bytes(envelope)) as BackupImportSuccess;
          expect(imported.data.photoId, isNull);
          final memory = MemoryStorage()..files[DataFile.current] = bytes(v3());
          final storage = HookStorage(memory);
          final state = PersistentPlanState(
            repository: KeepMyCarRepository(storage),
            referenceMonth: reference,
          );
          addTearDown(state.dispose);
          await state.load();
          final original = state.snapshot;
          final oldBytes = Map<DataFile, List<int>>.from(memory.files);
          final pending = Completer<void>();
          var fail = outcome != 'saved';
          storage.before = (op) async {
            if (op == 'prepare') await pending.future;
            if (fail && op == 'move.temp.current') {
              fail = outcome == 'uncertain';
              throw StateError('promotion/rollback failure');
            }
          };
          final request = state.restoreFromBackup(imported);
          expect(state.photoId, photoIdV3);
          if (outcome == 'saved') {
            pending.complete();
            await request;
            expect(state.snapshot.photoId, isNull);
            final saved = jsonDecode(
              utf8.decode(memory.files[DataFile.current]!),
            );
            expect(saved['formatVersion'], 3);
            expect(saved['photoId'], isNull);
            await state.load();
            expect(state.photoId, isNull);
          } else {
            final rejected = expectLater(
              request,
              throwsA(
                isA<SaveRequestFailure>().having(
                  (e) => e.uncertain,
                  'uncertain',
                  outcome == 'uncertain',
                ),
              ),
            );
            pending.complete();
            await rejected;
            expect(state.snapshot, original);
            if (outcome == 'failed') {
              expect(
                memory.files[DataFile.current],
                oldBytes[DataFile.current],
              );
            }
          }
        },
      );
    }
  }
  test('external export remains exact v2 schema and omits internal photo', () {
    final data = domain(v3());
    final exported = backup.encode(data, createdAt: DateTime.utc(2026, 10, 19));
    final root = jsonDecode(utf8.decode(exported));
    expect(root['exportFormatVersion'], 2);
    final expected = v3()
      ..remove('formatVersion')
      ..remove('photoId');
    expect(root['data'], expected);
    expect(root['data'].keys, [
      'ownerBirthMonth',
      'car',
      'planConditions',
      'plannedExpenses',
    ]);
    expect(
      (backup.decode(exported) as BackupImportSuccess).data.photoId,
      isNull,
    );
    expect(data.photoId, photoIdV3);
  });
  test('initialization has null photo and unused funding; clear/load discard old reference', () async {
    final repo = TestRepository(Loaded(domain(v3())));
    final state = PersistentPlanState(
      repository: repo,
      referenceMonth: reference,
    );
    addTearDown(state.dispose);
    await state.load();
    expect(state.photoId, photoIdV3);
    repo.result = const NoData();
    await state.load();
    expect(state.photoId, isNull);
    final original = domain(v3());
    final initial = (
      photoId: null,
      ownerBirthMonth: original.ownerBirthMonth,
      car: original.car,
      planConditions: newBasicPlanConditions(
        currentMileageKm: 45000,
        annualMileageKm: 4000,
        ownershipTargetAge: 70,
      ),
      plannedExpenses: original.plannedExpenses.take(0).toList(),
    );
    await state.initialize(initial);
    expect(state.snapshot.photoId, isNull);
    expect(repo.saves.single.photoId, isNull);
    expect(state.session!.conditions.fundingPlanEnabled, false);
    repo.result = Loaded(original);
    await state.load();
    repo.result = LoadFailure([saveFailure().issue]);
    await state.load();
    await state.discardFailureAndStartNew();
    expect(state.photoId, isNull);
    expect(state.car, isNull);
    expect(state.session, isNull);
  });
  test('initialize rejects nonnull photo without changing state or files', () async {
    final storage = MemoryStorage()..files[DataFile.temp] = [42];
    final state = PersistentPlanState(
      repository: KeepMyCarRepository(storage),
      referenceMonth: reference,
    );
    addTearDown(state.dispose);
    await state.load();
    expect(state.phase, StartupPhase.noData);
    final before = (
      state.phase,
      state.photoId,
      state.ownerBirthMonth,
      state.car,
      state.session,
    );
    final beforeFiles = Map<DataFile, List<int>>.from(storage.files);
    final source = domain(v3());
    // Every other initialize precondition is valid; only photoId is forbidden.
    final RestoredCarData candidate = (
      photoId: photoIdV3,
      ownerBirthMonth: source.ownerBirthMonth,
      car: source.car,
      planConditions: newBasicPlanConditions(
        currentMileageKm: 45000,
        annualMileageKm: 4000,
        ownershipTargetAge: 70,
      ),
      plannedExpenses: [],
    );
    await expectLater(
      state.initialize(candidate),
      throwsA(isA<SaveRequestFailure>()),
    );
    expect((
      state.phase,
      state.photoId,
      state.ownerBirthMonth,
      state.car,
      state.session,
    ), before);
    expect(storage.mutations, isEmpty);
    expect(storage.files, beforeFiles);
  });
  test(
    'VersionProtected clears an adopted photo without mutating files',
    () async {
      final storage = MemoryStorage()
        ..files[DataFile.current] = bytes(v3())
        ..files[DataFile.backup] = bytes(v2())
        ..files[DataFile.temp] = [42];
      final state = PersistentPlanState(
        repository: KeepMyCarRepository(storage),
        referenceMonth: reference,
      );
      addTearDown(state.dispose);
      await state.load();
      expect(state.phase, StartupPhase.ready);
      expect(state.snapshot.photoId, photoIdV3);
      storage.files[DataFile.current] = bytes({'formatVersion': 4});
      final beforeFiles = Map<DataFile, List<int>>.from(storage.files);
      await state.load();
      expect(state.versionProtection!.file, 'current');
      expect(state.versionProtection!.version, 4);
      expect(state.phase, StartupPhase.failure);
      expect(state.photoId, isNull);
      expect(state.ownerBirthMonth, isNull);
      expect(state.car, isNull);
      expect(state.session, isNull);
      expect(state.saveRestricted, true);
      expect(state.canRestoreBackup, false);
      await expectLater(
        state.restoreFromBackup(BackupImportSuccess(domain(v2()))),
        throwsA(isA<SaveRequestFailure>()),
      );
      await expectLater(
        state.discardFailureAndStartNew(),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(storage.mutations, isEmpty);
      expect(storage.files, beforeFiles);
    },
  );
  test('v3 photo reference needs no photo file and preserves Golden Sample calculations', () {
    final data = domain(v3());
    final plan = session(
      initial: data.planConditions,
      expenses: data.plannedExpenses,
    );
    expect(data.plannedExpenses, hasLength(6));
    expect(
      data.plannedExpenses.fold<int>(0, (sum, e) => sum + e.amountYen),
      2550000,
    );
    final result = plan.reserveResult as RepairReserveSuccess;
    expect(result.plannedExpensesOnlyMonthlyYen, 11341);
    expect(result.repairIncludedMonthlyYen, 29808);
    expect(result.additionalMonthlyYen, 18467);
    // Compare every displayed timeline input/result with the original sample,
    // including goal, owner/car ages, mileage and expense totals/order.
    final original = session();
    expect(plan.ownershipTargetMonth, original.ownershipTargetMonth);
    expect(
      [
        for (final year in plan.timeline)
          [
            year.year,
            year.ownerAge,
            year.carAge,
            year.mileageKm,
            year.isCurrent,
            year.totalYen,
            year.expenses.map((e) => e.id).toList(),
          ],
      ],
      [
        for (final year in original.timeline)
          [
            year.year,
            year.ownerAge,
            year.carAge,
            year.mileageKm,
            year.isCurrent,
            year.totalYen,
            year.expenses.map((e) => e.id).toList(),
          ],
      ],
    );
  });
}
