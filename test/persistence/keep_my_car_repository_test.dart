import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_json_codec.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import '../plan_test_support.dart';

const mapper = KeepMyCarDataMapper();
const codec = KeepMyCarJsonCodec();

RestoredCarData snapshot([String? name, YearMonth? birthMonth]) => (
  ownerBirthMonth: birthMonth ?? goldenSample.owner.birthMonth,
  car: goldenSample.car.copyWith(name: name),
  planConditions: conditions(),
  plannedExpenses: goldenSample.plannedExpenses,
);

List<int> bytes(RestoredCarData data) => utf8.encode(
  codec.encode(
    mapper.toDto(
      ownerBirthMonth: data.ownerBirthMonth,
      car: data.car,
      planConditions: data.planConditions,
      plannedExpenses: data.plannedExpenses,
    ),
  ),
);

/// Real filesystem underneath; hooks can fail before or after an operation,
/// including moves that took effect before returning an error.
class HookStorage implements LocalFileStorage {
  HookStorage(this.inner);
  final LocalFileStorage inner;
  FutureOr<void> Function(String operation)? before;
  FutureOr<void> Function(String operation)? after;
  final events = <String>[];

  Future<T> run<T>(String operation, Future<T> Function() action) async {
    events.add(operation);
    await before?.call(operation);
    final result = await action();
    await after?.call(operation);
    return result;
  }

  @override
  Future<void> prepare() => run('prepare', inner.prepare);
  @override
  Future<List<int>?> read(DataFile file) =>
      run('read.${file.name}', () => inner.read(file));
  @override
  Future<void> writeTemp(List<int> bytes) =>
      run('write.temp', () => inner.writeTemp(bytes));
  @override
  Future<void> move(DataFile source, DataFile destination) => run(
    'move.${source.name}.${destination.name}',
    () => inner.move(source, destination),
  );
  @override
  Future<void> delete(DataFile file) =>
      run('delete.${file.name}', () => inner.delete(file));
}

void main() {
  late Directory directory;
  late IoLocalFileStorage io;
  late HookStorage storage;
  late KeepMyCarRepository repository;

  File file(DataFile role) =>
      File('${directory.path}${Platform.pathSeparator}${role.fileName}');
  Future<void> put(DataFile role, List<int> data) async {
    await file(role).writeAsBytes(data, flush: true);
  }

  Future<void> seed() async {
    await put(DataFile.current, bytes(snapshot('B')));
    await put(DataFile.backup, bytes(snapshot('A')));
  }

  Future<void> expectOldFiles() async {
    expect(await io.read(DataFile.current), bytes(snapshot('B')));
    expect(await io.read(DataFile.backup), bytes(snapshot('A')));
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('keep_my_car_e2_');
    io = IoLocalFileStorage(directory: () async => directory);
    storage = HookStorage(io);
    repository = KeepMyCarRepository(storage);
  });
  tearDown(() async {
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    // Recursive cleanup is limited to this test's freshly created temp child.
    if (!target.startsWith('$root${Platform.pathSeparator}keep_my_car_e2_')) {
      throw StateError('Unsafe test cleanup path: $target');
    }
    await directory.delete(recursive: true);
  });

  test(
    'confirmed discard removes corrupt current, backup and stale temp',
    () async {
      for (final role in DataFile.values) {
        await put(role, utf8.encode('broken'));
      }
      expect(await repository.load(), isA<LoadFailure>());
      expect(await repository.discardUnreadableData(), isA<Saved>());
      for (final role in DataFile.values) {
        expect(await io.read(role), isNull);
      }
      expect(await repository.load(), isA<NoData>());
      expect(await repository.save(snapshot()), isA<Saved>());
      expect(await repository.load(), isA<Loaded>());
    },
  );

  for (final role in [DataFile.current, DataFile.backup]) {
    test(
      'discard refuses readable ${role.name} without deleting files',
      () async {
        await put(role, bytes(snapshot()));
        final result = await repository.discardUnreadableData() as SaveFailure;
        expect(result.rollbackIssues, isEmpty);
        expect(await io.read(role), bytes(snapshot()));
        expect(storage.events.where((e) => e.startsWith('delete')), isEmpty);
      },
    );
  }

  test('discard read failure leaves all files untouched', () async {
    await put(DataFile.current, utf8.encode('broken'));
    storage.before = (op) {
      if (op == 'read.current') throw StateError('read error');
    };
    final result = await repository.discardUnreadableData() as SaveFailure;
    expect(result.rollbackIssues, isEmpty);
    expect(await io.read(DataFile.current), utf8.encode('broken'));
    expect(storage.events.where((e) => e.startsWith('delete')), isEmpty);
  });

  test(
    'partial discard requires reload and does not claim preservation',
    () async {
      for (final role in DataFile.values) {
        await put(role, utf8.encode('broken'));
      }
      storage.before = (op) {
        if (op == 'delete.backup') throw StateError('delete error');
      };
      final result = await repository.discardUnreadableData() as SaveFailure;
      expect(result.rollbackIssues, isNotEmpty);
      expect(await io.read(DataFile.current), isNull);
      expect(await io.read(DataFile.backup), utf8.encode('broken'));
      expect(await repository.load(), isA<LoadFailure>());
    },
  );

  test(
    'ownerBirthMonth is retained in temp, current, backup and recovery',
    () async {
      final a = snapshot('A', const YearMonth(1970, 4));
      final b = snapshot('B', const YearMonth(1971, 5));
      final tempMonths = <String>[];
      storage.after = (op) async {
        if (op == 'write.temp') {
          final temp = jsonDecode(
            utf8.decode((await io.read(DataFile.temp))!),
          ) as Map<String, dynamic>;
          tempMonths.add(temp['ownerBirthMonth'] as String);
          expect(temp.containsKey('referenceMonth'), isFalse);
        }
      };
      expect(await repository.save(a), isA<Saved>());
      expect(
        (await repository.load() as Loaded).data.ownerBirthMonth,
        a.ownerBirthMonth,
      );
      expect(await repository.save(b), isA<Saved>());
      expect(
        (await repository.load() as Loaded).data.ownerBirthMonth,
        b.ownerBirthMonth,
      );
      expect(await io.read(DataFile.current), bytes(b));
      expect(await io.read(DataFile.backup), bytes(a));
      expect(tempMonths, ['1970-04', '1971-05']);
      await put(DataFile.current, utf8.encode('{broken'));
      expect(
        (await repository.load() as Recovered).data.ownerBirthMonth,
        a.ownerBirthMonth,
      );
    },
  );

  test(
    'normal current and corrupt backup save replaces backup with old current',
    () async {
      await put(DataFile.current, bytes(snapshot('B')));
      await put(DataFile.backup, utf8.encode('{broken'));
      expect(await repository.save(snapshot('C')), isA<Saved>());
      expect(await io.read(DataFile.current), bytes(snapshot('C')));
      expect(await io.read(DataFile.backup), bytes(snapshot('B')));
      expect((await repository.load() as Loaded).data.car.name, 'C');
    },
  );

  test(
    'corrupt current without backup saves without backing up corruption',
    () async {
      await put(DataFile.current, utf8.encode('{broken'));
      expect(await repository.save(snapshot('C')), isA<Saved>());
      expect(await io.read(DataFile.current), bytes(snapshot('C')));
      expect(await io.read(DataFile.backup), isNull);
      expect((await repository.load() as Loaded).data.car.name, 'C');
    },
  );

  test('current rollback succeeds and backup rollback fails without losing old current', () async {
    await seed();
    final promotionError = const FileSystemException('promotion failed');
    final backupError = const FileSystemException('backup rollback failed');
    var promotionFailed = false;
    storage.before = (op) {
      if (op == 'move.temp.current' && !promotionFailed) {
        promotionFailed = true;
        throw promotionError;
      }
      if (op == 'move.temp.backup') throw backupError;
    };
    final result = await repository.save(snapshot('C')) as SaveFailure;
    expect(result.issue.stage, PersistenceStage.promoteTemp);
    expect(result.issue.cause, same(promotionError));
    expect(result.rollbackIssues.single.stage, PersistenceStage.rollback);
    expect(result.rollbackIssues.single.cause, same(backupError));
    expect(await io.read(DataFile.current), bytes(snapshot('B')));
    expect(await io.read(DataFile.backup), bytes(snapshot('B')));
    expect((await repository.load() as Loaded).data.car.name, 'B');
  });

  test('first save creates verified UTF-8 current with no backup', () async {
    expect(await repository.save(snapshot()), isA<Saved>());
    expect(await io.read(DataFile.current), bytes(snapshot()));
    expect(await io.read(DataFile.backup), isNull);
    expect(await io.read(DataFile.temp), isNull);
    final loaded = await repository.load() as Loaded;
    expect(loaded.data.car.name, 'メルセデスAMG E53');
    expect(loaded.data.plannedExpenses.first.name, '12Vバッテリー');
    expect(bytes(loaded.data), bytes(snapshot()));
    expect(storage.events.take(7), [
      'prepare',
      'write.temp',
      'read.temp',
      'read.current',
      'move.temp.current',
      'read.current',
      'read.current',
    ]);
  });

  test(
    'second save retains A; third retains only B as one generation',
    () async {
      for (final name in ['A', 'B', 'C']) {
        expect(await repository.save(snapshot(name)), isA<Saved>());
        expect(await io.read(DataFile.current), bytes(snapshot(name)));
        expect(
          await io.read(DataFile.backup),
          name == 'A' ? isNull : bytes(snapshot(name == 'B' ? 'A' : 'B')),
        );
      }
      expect(await directory.list().length, 2);
      expect((await repository.load() as Loaded).data.car.name, 'C');
    },
  );

  test('creates a missing test directory only on save', () async {
    final child = Directory('${directory.path}${Platform.pathSeparator}nested');
    final repo = KeepMyCarRepository(
      IoLocalFileStorage(directory: () async => child),
    );
    expect(await repo.load(), isA<NoData>());
    expect(await child.exists(), isFalse);
    expect(await repo.save(snapshot()), isA<Saved>());
    expect(await repo.load(), isA<Loaded>());
  });

  test(
    'current wins without reading even a broken backup or stale temp',
    () async {
      await seed();
      await put(DataFile.backup, [0xff]);
      await put(DataFile.temp, bytes(snapshot('未確定')));
      expect((await repository.load() as Loaded).data.car.name, 'B');
      expect(storage.events, ['read.current']);
      expect(await io.read(DataFile.temp), bytes(snapshot('未確定')));
    },
  );

  for (final corrupt in [false, true]) {
    test(
      'backup recovery with ${corrupt ? 'corrupt' : 'missing'} current leaves files untouched',
      () async {
        if (corrupt) await put(DataFile.current, utf8.encode('{broken'));
        await put(DataFile.backup, bytes(snapshot('復旧')));
        final result = await repository.load() as Recovered;
        expect(result.data.car.name, '復旧');
        expect(result.currentIssue, corrupt ? isNotNull : isNull);
        expect(
          await io.read(DataFile.current),
          corrupt ? utf8.encode('{broken') : isNull,
        );
        expect(await io.read(DataFile.backup), bytes(snapshot('復旧')));
        expect(await repository.save(snapshot('再保存')), isA<Saved>());
        expect((await repository.load() as Loaded).data.car.name, '再保存');
        // Bad/missing current never overwrites the valid recovery source.
        expect(await io.read(DataFile.backup), bytes(snapshot('復旧')));
      },
    );
  }

  for (final roles in [
    [DataFile.current, DataFile.backup],
    [DataFile.current],
    [DataFile.backup],
  ]) {
    test('no usable data returns Failure for corrupt $roles', () async {
      for (final role in roles) {
        await put(role, utf8.encode('{broken'));
      }
      final result = await repository.load() as LoadFailure;
      expect(result.issues, hasLength(roles.length));
      expect(
        result.issues.every((issue) => issue.cause is FormatException),
        isTrue,
      );
    });
  }

  for (final temp in [false, true]) {
    test('NoData with no committed files, temp present: $temp', () async {
      if (temp) await put(DataFile.temp, bytes(snapshot('未確定')));
      expect(await repository.load(), isA<NoData>());
      expect(await io.read(DataFile.current), isNull);
      expect(storage.events, ['read.current', 'read.backup']);
    });
  }

  for (final spec in [
    ('prepare', PersistenceStage.prepare),
    ('write.temp', PersistenceStage.writeTemp),
    ('read.temp', PersistenceStage.verifyTemp),
    ('read.current', PersistenceStage.readCurrent),
    ('read.backup', PersistenceStage.readBackup),
    ('move.current.backup', PersistenceStage.backupCurrent),
    ('move.temp.current', PersistenceStage.promoteTemp),
  ]) {
    for (final after in [false, true]) {
      test(
        '${spec.$1} failure ${after ? 'after' : 'before'} operation preserves current and backup',
        () async {
          await seed();
          final cause = FileSystemException('injected ${spec.$1}');
          var fired = false;
          void hook(String op) {
            if (!fired && op == spec.$1) {
              fired = true;
              throw cause;
            }
          }

          if (after) {
            storage.after = hook;
          } else {
            storage.before = hook;
          }
          final result = await repository.save(snapshot('C')) as SaveFailure;
          expect(result.issue.stage, spec.$2);
          expect(result.issue.cause, same(cause));
          expect(result.rollbackIssues, isEmpty);
          await expectOldFiles();
          expect(await repository.save(snapshot('再試行')), isA<Saved>());
        },
      );
    }
  }

  for (final corruption in [
    'syntax',
    'version',
    'type',
    'domain',
    'utf8',
    'otherValid',
  ]) {
    test('temp $corruption cannot change current or backup', () async {
      await seed();
      storage.after = (op) async {
        if (op != 'write.temp') return;
        final data = jsonDecode(
          utf8.decode(bytes(snapshot('C'))),
        ) as Map<String, dynamic>;
        switch (corruption) {
          case 'syntax':
            await io.writeTemp(utf8.encode('{'));
            break;
          case 'version':
            data['formatVersion'] = 2;
            await io.writeTemp(utf8.encode(jsonEncode(data)));
            break;
          case 'type':
            data['car']['name'] = 123;
            await io.writeTemp(utf8.encode(jsonEncode(data)));
            break;
          case 'domain':
            data['car']['name'] = '';
            await io.writeTemp(utf8.encode(jsonEncode(data)));
            break;
          case 'utf8':
            await io.writeTemp([0xff]);
            break;
          case 'otherValid':
            await io.writeTemp(bytes(snapshot('別データ')));
            break;
        }
      };
      final result = await repository.save(snapshot('C')) as SaveFailure;
      expect(result.issue.stage, PersistenceStage.verifyTemp);
      expect(
        result.issue.cause,
        corruption == 'domain'
            ? isA<ArgumentError>()
            : corruption == 'otherValid'
            ? isA<StateError>()
            : isA<FormatException>(),
      );
      expect(storage.events.any((event) => event.startsWith('move.')), isFalse);
      await expectOldFiles();
    });
  }

  test('invalid snapshot fails before file operations', () async {
    await seed();
    final bad = snapshot();
    final result = await repository.save((
      ownerBirthMonth: goldenSample.owner.birthMonth,
      car: bad.car.copyWith(name: ''),
      planConditions: bad.planConditions,
      plannedExpenses: bad.plannedExpenses,
    )) as SaveFailure;
    expect(result.issue.stage, PersistenceStage.encode);
    expect(storage.events, isEmpty);
    await expectOldFiles();
  });

  test(
    'backup move losing destination before failure rolls back both files',
    () async {
      await seed();
      storage.before = (op) async {
        if (op == 'move.current.backup') {
          await io.delete(DataFile.backup);
          throw const FileSystemException('destination removed, rename failed');
        }
      };
      final result = await repository.save(snapshot('C')) as SaveFailure;
      expect(result.rollbackIssues, isEmpty);
      await expectOldFiles();
    },
  );

  for (final failure in ['read', 'corrupt', 'missing']) {
    test(
      'final current $failure fails save and rolls back both files',
      () async {
        await seed();
        var promoted = false;
        var fired = false;
        storage.after = (op) async {
          if (op == 'move.temp.current' && !fired) {
            promoted = true;
            if (failure == 'corrupt') {
              await put(DataFile.current, utf8.encode('{'));
            }
            if (failure == 'missing') await io.delete(DataFile.current);
          }
        };
        storage.before = (op) {
          if (promoted && !fired && op == 'read.current') {
            fired = true;
            if (failure == 'read') {
              throw const FileSystemException('final read failed');
            }
          }
        };
        final result = await repository.save(snapshot('C')) as SaveFailure;
        expect(result.issue.stage, PersistenceStage.verifyCurrent);
        expect(result.rollbackIssues, isEmpty);
        await expectOldFiles();
      },
    );
  }

  test(
    'backup verification failure triggers rollback before promotion',
    () async {
      await seed();
      var reads = 0;
      storage.before = (op) {
        if (op == 'read.backup' && ++reads == 2) {
          throw const FileSystemException('verify backup');
        }
      };
      final result = await repository.save(snapshot('C')) as SaveFailure;
      expect(result.issue.stage, PersistenceStage.backupCurrent);
      await expectOldFiles();
    },
  );

  test(
    'rollback failure retains old current in backup and both causes',
    () async {
      await seed();
      var promotionFailed = false;
      storage.before = (op) {
        if (op == 'move.temp.current') {
          promotionFailed = true;
          throw const FileSystemException('promotion failure');
        }
        if (promotionFailed && op == 'write.temp') {
          throw const FileSystemException('rollback failure');
        }
      };
      final result = await repository.save(snapshot('C')) as SaveFailure;
      expect(result.issue.stage, PersistenceStage.promoteTemp);
      expect(result.rollbackIssues.single.stage, PersistenceStage.rollback);
      expect(await io.read(DataFile.backup), bytes(snapshot('B')));
      final recovered = await repository.load() as Recovered;
      expect(recovered.data.car.name, 'B');
    },
  );

  test('read error is not NoData and backup can still recover', () async {
    await put(DataFile.backup, bytes(snapshot('A')));
    final cause = const FileSystemException('permission denied');
    storage.before = (op) {
      if (op == 'read.current') throw cause;
    };
    final recovered = await repository.load() as Recovered;
    expect(recovered.currentIssue!.cause, same(cause));
    await io.delete(DataFile.backup);
    final failure = await repository.load() as LoadFailure;
    expect(failure.issues.single.cause, same(cause));
  });

  test('directory provider failure preserves original exception', () async {
    final cause = StateError('directory unavailable');
    final repo = KeepMyCarRepository(
      IoLocalFileStorage(directory: () async => throw cause),
    );
    expect((await repo.load() as LoadFailure).issues.first.cause, same(cause));
    final save = await repo.save(snapshot()) as SaveFailure;
    expect(save.issue.stage, PersistenceStage.prepare);
    expect(save.issue.cause, same(cause));
  });

  test(
    'guard prevents overlapping saves and load observing intermediate state',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      storage.before = (op) async {
        if (op == 'write.temp') {
          entered.complete();
          await release.future;
        }
      };
      final first = repository.save(snapshot('A'));
      await entered.future;
      expect(
        (await repository.save(snapshot('B')) as SaveFailure).issue.stage,
        PersistenceStage.busy,
      );
      expect(
        (await repository.load() as LoadFailure).issues.single.stage,
        PersistenceStage.busy,
      );
      release.complete();
      expect(await first, isA<Saved>());
      expect((await repository.load() as Loaded).data.car.name, 'A');
    },
  );

  test(
    'captured snapshot is unaffected by caller list mutation during I/O',
    () async {
      final expenses = goldenSample.plannedExpenses.toList();
      storage.before = (op) {
        if (op == 'prepare') expenses.clear();
      };
      expect(
        await repository.save((
          ownerBirthMonth: goldenSample.owner.birthMonth,
          car: goldenSample.car,
          planConditions: conditions(),
          plannedExpenses: expenses,
        )),
        isA<Saved>(),
      );
      expect(
        (await repository.load() as Loaded).data.plannedExpenses,
        hasLength(6),
      );
    },
  );

  test(
    'interrupted rotation state recovers backup and ignores valid temp',
    () async {
      await put(DataFile.backup, bytes(snapshot('B')));
      await put(DataFile.temp, bytes(snapshot('C')));
      expect((await repository.load() as Recovered).data.car.name, 'B');
      expect(await io.read(DataFile.current), isNull);
    },
  );

  test(
    'Golden Sample real-file round trip retains Step 8 and Step 9',
    () async {
      expect(await repository.save(snapshot()), isA<Saved>());
      final restored = (await repository.load() as Loaded).data;
      expect(restored.ownerBirthMonth, const YearMonth(1970, 4));
      expect(bytes(restored), bytes(snapshot()));
      final before = session();
      final after = session(
        birth: restored.ownerBirthMonth,
        initial: restored.planConditions,
        registration: restored.car.firstRegistrationMonth,
        expenses: restored.plannedExpenses,
      );
      final result = after.reserveResult as RepairReserveSuccess;
      expect(result.plannedExpensesOnlyMonthlyYen, 11341);
      expect(result.repairIncludedMonthlyYen, 29808);
      expect(result.additionalMonthlyYen, 18467);
      expect(after.timeline, hasLength(10));
      for (var i = 0; i < 10; i++) {
        final a = after.timeline[i];
        final b = before.timeline[i];
        expect(
          [
            a.year,
            a.ownerAge,
            a.carAge,
            a.mileageKm,
            a.isCurrent,
            a.totalYen,
            a.expenses.map((e) => e.id).toList(),
          ],
          [
            b.year,
            b.ownerAge,
            b.carAge,
            b.mileageKm,
            b.isCurrent,
            b.totalYen,
            b.expenses.map((e) => e.id).toList(),
          ],
        );
      }
    },
  );
}
