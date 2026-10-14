import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/plan_session.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/app/save_request.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_transfer.dart';
import 'package:keep_my_car/domain/models/plan_conditions.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/plan_conditions_validation.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_json_codec.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';

import 'plan_test_support.dart';
import 'persistence/keep_my_car_persistence_test.dart' show wire;
import 'backup/fixtures/backup_v1_fixture.dart';

class MemoryStorage implements LocalFileStorage {
  final files = <DataFile, List<int>>{};
  final mutations = <String>[];
  bool failPromotion = false;
  @override
  Future<void> prepare() async {
    mutations.add('prepare');
  }

  @override
  Future<List<int>?> read(DataFile file) async => files[file]?.toList();
  @override
  Future<void> writeTemp(List<int> bytes) async {
    mutations.add('temp');
    files[DataFile.temp] = bytes.toList();
  }

  @override
  Future<void> move(DataFile source, DataFile destination) async {
    mutations.add('move');
    if (failPromotion &&
        source == DataFile.temp &&
        destination == DataFile.current) {
      failPromotion = false;
      throw StateError('promotion');
    }
    files[destination] = files.remove(source)!;
  }

  @override
  Future<void> delete(DataFile file) async {
    mutations.add('delete');
    files.remove(file);
  }
}

const mapper = KeepMyCarDataMapper();
const codec = KeepMyCarJsonCodec();
List<int> bytes(Object root) => utf8.encode(jsonEncode(root));
Map<String, dynamic> v2({
  bool enabled = true,
  int ownership = 70,
  int age = 65,
}) {
  final root = wire()..['formatVersion'] = 2;
  root['planConditions']['fundingPlanEnabled'] = enabled;
  root['planConditions']['ownershipTargetAge'] = ownership;
  root['planConditions']['reserveTargetAge'] = age;
  return root;
}

RestoredCarData domain(Map<String, dynamic> root) =>
    mapper.toDomain(codec.decode(jsonEncode(root)));
PlanConditions toggle(PlanConditions saved, bool enabled) => PlanConditions(
  fundingPlanEnabled: enabled,
  currentMileageKm: saved.currentMileageKm,
  annualMileageKm: saved.annualMileageKm,
  ownershipTargetAge: saved.ownershipTargetAge,
  currentCarFundYen: saved.currentCarFundYen,
  reserveTargetAge: saved.reserveTargetAge,
  largeRepairReserveYen: saved.largeRepairReserveYen,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final backupVersion in [1, 2]) {
    test('Backup v$backupVersion explicitly selects its validation schema', () {
      final root = jsonDecode(backupV1Fixture) as Map<String, dynamic>;
      root['exportFormatVersion'] = backupVersion;
      // Payload metadata cannot override the envelope's validation selection.
      root['data']['formatVersion'] = backupVersion == 1 ? 2 : 1;
      root['data']['planConditions']['fundingPlanEnabled'] = false;
      const backup = BackupV1Codec();
      final valid = backup.decode(bytes(root)) as BackupImportSuccess;
      expect(valid.data.planConditions.fundingPlanEnabled, backupVersion == 1);
      root['data']['planConditions']['reserveTargetAge'] = 100;
      final reversed = backup.decode(bytes(root));
      if (backupVersion == 1) {
        expect(
          (reversed as BackupImportFailure).issue,
          BackupImportIssue.invalidContent,
        );
      } else {
        expect(
          (reversed as BackupImportSuccess)
              .data
              .planConditions
              .reserveTargetAge,
          100,
        );
      }
    });
  }

  for (final entry in [
    (50, 55, const YearMonth(2026, 9), PlanInputError.pastTargetMonth),
    (60, 65, const YearMonth(2026, 9), PlanInputError.exceedsOwnershipAge),
    (70, 56, const YearMonth(2026, 9), PlanInputError.pastTargetMonth),
    (56, 56, const YearMonth(2026, 4), null),
    (65, 65, const YearMonth(2026, 9), null),
  ]) {
    test('shared funding preconditions preserve boundary/priority $entry', () {
      final input = conditions(ownership: entry.$1, age: entry.$2);
      expect(
        fundingPlanPreconditionError(
          input,
          birthMonth: const YearMonth(1970, 4),
          referenceMonth: entry.$3,
        ),
        entry.$4,
      );
      final errors = validateFundingPlanConditions(
        input,
        birthMonth: const YearMonth(1970, 4),
        referenceMonth: entry.$3,
      );
      expect(errors[PlanField.reserveAge], entry.$4);
      // The legacy editor keeps the same reserve error and priority.
      expect(
        validatePlanConditions(
          input,
          birthMonth: const YearMonth(1970, 4),
          referenceMonth: entry.$3,
        )[PlanField.reserveAge],
        entry.$4,
      );
      final calls = CalculationCalls();
      final plan = session(
        initial: input,
        reference: entry.$3,
        reserveCalculator: calls.calculateReserve,
      );
      expect(
        plan.fundingPlanStatus,
        entry.$4 == null
            ? FundingPlanStatus.calculable
            : FundingPlanStatus.needsReview,
      );
      expect(calls.reserve, entry.$4 == null ? 1 : 0);
    });
  }

  for (final entry in <(String, Object?)>[
    ('missing', null),
    ('null', null),
    ('string', 'true'),
    ('int', 1),
    ('double', 1.0),
    ('list', <Object>[]),
    ('object', <String, Object>{}),
  ]) {
    test(
      'Backup v2 ${entry.$1} bool rejects import without mutation',
      () async {
        final root = jsonDecode(backupV1Fixture) as Map<String, dynamic>;
        root['exportFormatVersion'] = 2;
        final plan = root['data']['planConditions'] as Map<String, dynamic>;
        if (entry.$1 == 'missing') {
          plan.remove('fundingPlanEnabled');
        } else {
          plan['fundingPlanEnabled'] = entry.$2;
        }
        final importedBytes = bytes(root);
        expect(
          (const BackupV1Codec().decode(
            importedBytes,
          ) as BackupImportFailure).issue,
          BackupImportIssue.invalidStructure,
        );
        final storage = MemoryStorage()
          ..files[DataFile.current] = bytes(v2())
          ..files[DataFile.backup] = bytes(wire())
          ..files[DataFile.temp] = [42];
        final originalFiles = Map<DataFile, List<int>>.from(storage.files);
        final state = PersistentPlanState(
          repository: KeepMyCarRepository(storage),
          referenceMonth: const YearMonth(2026, 9),
        );
        addTearDown(state.dispose);
        await state.load();
        final originalSession = state.session;
        final originalCar = state.car;
        final originalPhase = state.phase;
        const channel = MethodChannel('keep_my_car/backup_file');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'read');
          return {
            'status': 'success',
            'bytes': Uint8List.fromList(importedBytes),
          };
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final result = await BackupTransfer(state: state).readCandidate();
        expect(result.status, BackupTransferStatus.error);
        expect(result.importIssue, BackupImportIssue.invalidStructure);
        expect(result.candidate, isNull);
        expect(state.session, same(originalSession));
        expect(state.car, same(originalCar));
        expect(state.phase, originalPhase);
        expect(storage.mutations, isEmpty);
        expect(storage.files, originalFiles);
      },
    );
  }

  test('invalid formal input rejects before auxiliary execution', () {
    final calls = CalculationCalls();
    expect(
      () => session(
        initial: conditions(fund: -1),
        reserveCalculator: calls.calculateReserve,
      ),
      throwsArgumentError,
    );
    expect(calls.reserve, 0);
  });
  test(
    'new basic initialization persists false and zero auxiliary values',
    () async {
      final storage = MemoryStorage();
      final state = PersistentPlanState(
        repository: KeepMyCarRepository(storage),
        referenceMonth: const YearMonth(2026, 9),
      );
      addTearDown(state.dispose);
      await state.load();
      final source = domain(wire());
      final plan = newBasicPlanConditions(
        currentMileageKm: source.car.currentMileageKm,
        annualMileageKm: source.car.annualMileageKm,
        ownershipTargetAge: 70,
      );
      await state.initialize((
        ownerBirthMonth: source.ownerBirthMonth,
        car: source.car,
        planConditions: plan,
        plannedExpenses: [],
      ));
      await state.load();
      expect(state.session!.conditions, plan);
      expect(state.session!.fundingPlanStatus, FundingPlanStatus.unused);
      expect(state.session!.timeline, isNotEmpty);
    },
  );
  test('new unused values; explicit bool equality/hash; legacy true', () {
    final plan = newBasicPlanConditions(
      currentMileageKm: 45000,
      annualMileageKm: 4000,
      ownershipTargetAge: 70,
    );
    expect(plan.fundingPlanEnabled, false);
    expect(
      [
        plan.currentCarFundYen,
        plan.reserveTargetAge,
        plan.largeRepairReserveYen,
      ],
      [0, 0, 0],
    );
    expect(plan, isNot(toggle(plan, true)));
    expect({plan, toggle(plan, true)}.length, 2);
    expect(toggle(plan, false).hashCode, plan.hashCode);
    expect(domain(wire()).planConditions.fundingPlanEnabled, true);
  });
  test('v1 ordering strict; v2 reversed retained; unused ranges checked', () {
    final old = wire();
    old['planConditions']['reserveTargetAge'] = 71;
    expect(() => domain(old), throwsArgumentError);
    expect(domain(v2(ownership: 60)).planConditions.reserveTargetAge, 65);
    for (final enabled in [true, false]) {
      final root = v2(enabled: enabled);
      root['planConditions']['currentCarFundYen'] = -1;
      expect(() => domain(root), throwsArgumentError);
    }
  });
  for (final value in [null, 1, 'true', 1.0]) {
    test('v2 bool rejects ${value.runtimeType}', () {
      final root = v2();
      root['planConditions']['fundingPlanEnabled'] = value;
      expect(() => domain(root), throwsFormatException);
    });
  }
  test('v2 bool missing rejects', () {
    final root = v2();
    (root['planConditions'] as Map).remove('fundingPlanEnabled');
    expect(() => domain(root), throwsFormatException);
  });
  test(
    'same expenses rejudge; basic independent; disable/re-enable validation',
    () {
      final calls = CalculationCalls();
      final plan = session(
        expenses: [],
        reserveCalculator: calls.calculateReserve,
      );
      calls.reset();
      expect(plan.applyBasic(conditions(ownership: 60, fund: -1)), isEmpty);
      expect(plan.conditions.currentCarFundYen, 500000);
      expect(plan.conditions.fundingPlanEnabled, true);
      expect(plan.fundingPlanStatus, FundingPlanStatus.needsReview);
      expect(calls.reserve, 0);
      expect(plan.reserveResult, isA<RepairReserveNeedsReview>());
      expect(plan.reservePending, false);
      expect(plan.reserveDeltaYen, null);
      expect(plan.applyFunding(toggle(plan.conditions, false)), isEmpty);
      expect(plan.fundingPlanStatus, FundingPlanStatus.unused);
      expect(plan.conditions.reserveTargetAge, 65);
      expect(
        plan.applyFunding(toggle(plan.conditions, true)),
        contains(PlanField.reserveAge),
      );
      expect(plan.applyBasic(conditions(ownership: 70)), isEmpty);
      expect(plan.applyFunding(toggle(plan.conditions, true)), isEmpty);
      expect(plan.fundingPlanStatus, FundingPlanStatus.calculable);
      expect(calls.reserve, 1);
      expect(plan.reserveDeltaYen, null);
    },
  );
  test('pending invalidates across stop and restart', () {
    final plan = session();
    plan.applyFunding(conditions(reserve: 3000000));
    expect(plan.reservePending, true);
    plan.applyFunding(toggle(plan.conditions, false));
    expect(plan.reservePending, false);
    expect(plan.reserveDeltaYen, null);
    plan.acknowledgeReserve();
    plan.applyFunding(toggle(plan.conditions, true));
    expect(plan.reservePending, false);
    expect(plan.reserveDeltaYen, null);
  });
  test('past target skips engine, disable allowed; same month calculable', () {
    final calls = CalculationCalls();
    final plan = session(
      initial: conditions(age: 56),
      reference: const YearMonth(2026, 9),
      reserveCalculator: calls.calculateReserve,
    );
    expect(plan.fundingPlanStatus, FundingPlanStatus.needsReview);
    expect(calls.reserve, 0);
    expect(plan.applyFunding(toggle(plan.conditions, false)), isEmpty);
    expect(
      session(
        initial: conditions(age: 56, ownership: 56),
        reference: const YearMonth(2026, 4),
      ).fundingPlanStatus,
      FundingPlanStatus.calculable,
    );
  });
  test('engine failure distinct from unused/review and zero', () {
    final plan = session(
      reserveCalculator: ({
        required referenceMonth,
        required currentCarFundYen,
        required reserveTargetMonth,
        required largeRepairReserveYen,
        required plannedExpenses,
      }) => const RepairReserveFailure(RepairReserveError.inconsistentResult),
    );
    expect(plan.fundingPlanStatus, FundingPlanStatus.calculationFailed);
    expect(plan.reserveDeltaYen, null);
    expect(plan.reservePending, false);
  });
  test(
    'Backup v1 strict migration; v2 round trip externally selects rules',
    () {
      const backup = BackupV1Codec();
      final legacy =
          backup.decode(utf8.encode(backupV1Fixture)) as BackupImportSuccess;
      expect(legacy.data.planConditions.fundingPlanEnabled, true);
      final invalid = jsonDecode(backupV1Fixture);
      invalid['data']['planConditions']['reserveTargetAge'] = 100;
      expect(backup.decode(bytes(invalid)), isA<BackupImportFailure>());
      for (final enabled in [true, false]) {
        final data = domain(v2(enabled: enabled, ownership: 60));
        final exported = backup.encode(data, createdAt: DateTime.utc(2026));
        final root = jsonDecode(utf8.decode(exported));
        expect(root['exportFormatVersion'], 2);
        root['data']['formatVersion'] = 999;
        final result = backup.decode(bytes(root)) as BackupImportSuccess;
        expect(result.data.planConditions, data.planConditions);
        expect(
          result.data.plannedExpenses.map((e) => e.id),
          data.plannedExpenses.map((e) => e.id),
        );
      }
      for (final version in [null, 0, -1, 1.0, true, '2', 3]) {
        final root = jsonDecode(backupV1Fixture);
        root['exportFormatVersion'] = version;
        expect(
          (backup.decode(bytes(root)) as BackupImportFailure).issue,
          version == 3
              ? BackupImportIssue.unsupportedVersion
              : BackupImportIssue.invalidStructure,
        );
      }
    },
  );
  test(
    'v1 bytes unchanged on load; explicit v2 save/reload retains v1 backup',
    () async {
      final storage = MemoryStorage()..files[DataFile.current] = bytes(wire());
      final repo = KeepMyCarRepository(storage);
      final result = await repo.load() as Loaded;
      expect(storage.mutations, isEmpty);
      expect(storage.files[DataFile.current], bytes(wire()));
      expect(await repo.save(result.data), isA<Saved>());
      expect(
        jsonDecode(
          utf8.decode(storage.files[DataFile.current]!),
        )['formatVersion'],
        2,
      );
      expect(storage.files[DataFile.backup], bytes(wire()));
      expect(
        (await repo.load() as Loaded).data.planConditions,
        result.data.planConditions,
      );
    },
  );
  for (final current in ['future', 'valid', 'missing', 'corrupt']) {
    test(
      'future protection: $current current, future backup; zero mutations',
      () async {
        final storage = MemoryStorage();
        final future = bytes({'formatVersion': 3, 'unknown': 'schema'});
        if (current == 'future') storage.files[DataFile.current] = future;
        if (current == 'valid') storage.files[DataFile.current] = bytes(v2());
        if (current == 'corrupt') {
          storage.files[DataFile.current] = bytes({'formatVersion': false});
        }
        storage.files[DataFile.backup] = current == 'future'
            ? bytes(wire())
            : future;
        storage.files[DataFile.temp] = [42];
        final original = Map<DataFile, List<int>>.from(storage.files);
        final repo = KeepMyCarRepository(storage);
        final loaded = await repo.load();
        if (current == 'valid') {
          expect((loaded as Loaded).unsupportedBackupVersion, 3);
        } else {
          expect(loaded, isA<VersionProtected>());
        }
        expect(await repo.save(domain(v2())), isA<SaveFailure>());
        expect(await repo.discardUnreadableData(), isA<SaveFailure>());
        final state = PersistentPlanState(
          repository: repo,
          referenceMonth: const YearMonth(2026, 9),
        );
        addTearDown(state.dispose);
        await state.load();
        expect(state.saveRestricted, true);
        expect(state.canRestoreBackup, false);
        if (current != 'valid') expect(state.versionProtection, isNotNull);
        await expectLater(
          state.restoreFromBackup(BackupImportSuccess(domain(wire()))),
          throwsA(isA<SaveRequestFailure>()),
        );
        await expectLater(
          state.discardFailureAndStartNew(),
          throwsA(isA<SaveRequestFailure>()),
        );
        expect(storage.mutations, isEmpty);
        expect(storage.files, original);
      },
    );
  }
  for (final version in [null, 0, -1, 1.0, true, '3']) {
    test(
      'invalid version ${version.runtimeType} recovers normal backup',
      () async {
        final storage = MemoryStorage()
          ..files[DataFile.current] = bytes({'formatVersion': version})
          ..files[DataFile.backup] = bytes(v2());
        expect(await KeepMyCarRepository(storage).load(), isA<Recovered>());
        expect(storage.mutations, isEmpty);
      },
    );
  }
  for (final backupVersion in [1, 2]) {
    test(
      'mixed recovery/rollback preserves bytes, backup v$backupVersion',
      () async {
        final storage = MemoryStorage()
          ..files[DataFile.current] = [1, 2]
          ..files[DataFile.backup] = bytes(backupVersion == 1 ? wire() : v2());
        final repo = KeepMyCarRepository(storage);
        expect(await repo.load(), isA<Recovered>());
        storage.files[DataFile.current] = bytes(
          backupVersion == 1 ? v2() : wire(),
        );
        final before = Map<DataFile, List<int>>.from(storage.files);
        storage.failPromotion = true;
        final result =
            await repo.save(domain(v2(enabled: false))) as SaveFailure;
        expect(result.rollbackIssues, isEmpty);
        expect(storage.files[DataFile.current], before[DataFile.current]);
        expect(storage.files[DataFile.backup], before[DataFile.backup]);
      },
    );
  }
  test(
    'persistent split saves sync Car; protection rechecked before save',
    () async {
      final storage = MemoryStorage()..files[DataFile.current] = bytes(v2());
      final state = PersistentPlanState(
        repository: KeepMyCarRepository(storage),
        referenceMonth: const YearMonth(2026, 9),
      );
      addTearDown(state.dispose);
      await state.load();
      expect(
        await state.applyBasic(
          conditions(ownership: 60, mileage: 123, annual: 456, fund: -1),
        ),
        isEmpty,
      );
      expect(state.car!.currentMileageKm, 123);
      expect(state.car!.annualMileageKm, 456);
      expect(state.session!.conditions.currentCarFundYen, 500000);
      expect(state.session!.fundingPlanStatus, FundingPlanStatus.needsReview);
      expect(
        await state.applyFunding(toggle(state.session!.conditions, false)),
        isEmpty,
      );
      await state.load();
      expect(state.session!.conditions.fundingPlanEnabled, false);
      expect(state.session!.conditions.reserveTargetAge, 65);
      storage.files[DataFile.backup] = bytes({'formatVersion': 3});
      final before = state.session!.conditions;
      await expectLater(
        Future.sync(() => state.applyBasic(conditions(ownership: 80))),
        throwsA(isA<SaveRequestFailure>()),
      );
      expect(state.session!.conditions, before);
      await state.load();
      expect(state.saveRestricted, true);
      expect(state.canRestoreBackup, false);
      expect(state.session, isNotNull);
    },
  );
}
