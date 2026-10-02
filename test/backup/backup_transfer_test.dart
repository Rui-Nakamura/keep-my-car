import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_transfer.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/backup_file/backup_file_gateway.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';

import '../persistence_app_support.dart';
import '../plan_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keep_my_car/backup_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = BackupV1Codec();
  final time = DateTime(2026, 10, 2, 12, 34, 56);
  final restored = sampleSnapshot(session(initial: conditions(fund: 876543)));
  final bytes = codec.encode(restored, createdAt: time);
  late TestRepository repo;
  late PersistentPlanState state;
  late BackupTransfer transfer;

  Future<void> start(LoadResult result) async {
    repo = TestRepository(result);
    state = PersistentPlanState(
      repository: repo,
      referenceMonth: const YearMonth(2026, 10),
    );
    await state.load();
    transfer = BackupTransfer(state: state, now: () => time);
  }

  setUp(() => start(Loaded(sampleSnapshot())));
  tearDown(() {
    state.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final status in ['success', 'cancelled', 'error']) {
    test(
      'export $status uses formal UTF-8 v1 without state mutation',
      () async {
        final old = state.snapshot;
        final oldSession = state.session;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'save');
          expect(
            call.arguments['filename'],
            'KeepMyCar_Backup_20261002_123456.kmcbackup',
          );
          expect(call.arguments['mimeType'], 'application/octet-stream');
          final decoded = codec.decode(
            call.arguments['bytes'] as Uint8List,
          ) as BackupImportSuccess;
          expect(decoded.data.car.name, old.car.name);
          expect(decoded.data.planConditions, old.planConditions);
          expect(
            jsonDecode(
              utf8.decode(call.arguments['bytes'] as Uint8List),
            )['exportFormatVersion'],
            1,
          );
          return {'status': status, if (status == 'error') 'code': 'ioFailure'};
        });
        expect((await transfer.export()).status, switch (status) {
          'success' => BackupTransferStatus.success,
          'cancelled' => BackupTransferStatus.cancelled,
          _ => BackupTransferStatus.error,
        });
        expect(state.session, same(oldSession));
        expect(state.car, same(old.car));
        expect(repo.saves, isEmpty);
      },
    );
  }

  test(
    'recovered export preserves phase and uses formal recovered input',
    () async {
      state.dispose();
      await start(Recovered(restored));
      messenger.setMockMethodCallHandler(channel, (call) async {
        final decoded = codec.decode(
          call.arguments['bytes'] as Uint8List,
        ) as BackupImportSuccess;
        expect(decoded.data.planConditions, restored.planConditions);
        return {'status': 'success'};
      });
      final session = state.session;
      expect((await transfer.export()).status, BackupTransferStatus.success);
      expect(state.phase, StartupPhase.recovered);
      expect(state.session, same(session));
      expect(repo.saves, isEmpty);
    },
  );

  for (final issue in BackupImportIssue.values) {
    test('read rejects ${issue.name} before candidate or save', () async {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      switch (issue) {
        case BackupImportIssue.notBackup:
          json['format'] = 'other';
        case BackupImportIssue.unsupportedVersion:
          json['exportFormatVersion'] = 2;
        case BackupImportIssue.invalidStructure:
          json.remove('data');
        case BackupImportIssue.invalidContent:
          json['data']['car']['currentMileageKm'] = -1;
      }
      final old = state.session;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'status': 'success',
          'bytes': Uint8List.fromList(utf8.encode(jsonEncode(json))),
        },
      );
      final result = await transfer.readCandidate();
      expect(result.status, BackupTransferStatus.error);
      expect(result.importIssue, issue);
      expect(result.candidate, isNull);
      expect(state.session, same(old));
      expect(repo.saves, isEmpty);
    });
  }

  for (final origin in ['ready', 'failure', 'noData']) {
    for (final success in [true, false]) {
      test(
        '$origin read then restore $success adopts only after Safe Save',
        () async {
          state.dispose();
          await start(switch (origin) {
            'ready' => Loaded(sampleSnapshot()),
            'failure' => LoadFailure([saveFailure().issue]),
            _ => const NoData(),
          });
          final oldPhase = state.phase;
          final oldSession = state.session;
          messenger.setMockMethodCallHandler(
            channel,
            (_) async => {'status': 'success', 'bytes': bytes},
          );
          final read = await transfer.readCandidate();
          expect(read.status, BackupTransferStatus.candidate);
          expect(repo.saves, isEmpty);
          expect(state.phase, oldPhase);
          final pending = Completer<SaveResult>();
          repo.onSave = (_) => pending.future;
          final request = transfer.restore(read.candidate!);
          expect(state.phase, oldPhase);
          expect(state.session, same(oldSession));
          pending.complete(success ? const Saved() : saveFailure());
          final result = await request;
          expect(
            result.status,
            success ? BackupTransferStatus.success : BackupTransferStatus.error,
          );
          if (success) {
            expect(state.phase, StartupPhase.ready);
            expect(state.snapshot.planConditions, restored.planConditions);
            await state.load();
            expect(state.snapshot.planConditions, restored.planConditions);
          } else {
            expect(state.phase, oldPhase);
            expect(state.session, same(oldSession));
            expect(result.saveFailure!.uncertain, false);
          }
        },
      );
    }
    for (final response in [
      {'status': 'cancelled'},
      {'status': 'error', 'code': 'timeout'},
      {
        'status': 'success',
        'bytes': Uint8List(BackupFileGateway.maxReadBytes + 1),
      },
    ]) {
      test(
        '$origin read ${response['status']}/${response['code']} preserves state',
        () async {
          state.dispose();
          await start(switch (origin) {
            'ready' => Loaded(sampleSnapshot()),
            'failure' => LoadFailure([saveFailure().issue]),
            _ => const NoData(),
          });
          final oldPhase = state.phase;
          final old = state.session;
          messenger.setMockMethodCallHandler(channel, (_) async => response);
          final result = await transfer.readCandidate();
          expect(
            result.status,
            response['status'] == 'cancelled'
                ? BackupTransferStatus.cancelled
                : BackupTransferStatus.error,
          );
          if (response['bytes'] != null) {
            expect(result.fileError, BackupFileError.tooLarge);
          }
          expect(state.phase, oldPhase);
          expect(state.session, same(old));
          expect(repo.saves, isEmpty);
        },
      );
    }
  }

  test('uncertain restore retains existing recovery contract', () async {
    repo.saveResult = saveFailure(uncertain: true);
    final candidate = codec.decode(bytes) as BackupImportSuccess;
    final result = await transfer.restore(candidate);
    expect(result.saveFailure!.uncertain, true);
    expect(state.phase, StartupPhase.uncertain);
  });

  test(
    'exactly 5 MiB content validates and confirmation cancel never saves',
    () async {
      final padded = Uint8List.fromList([
        ...bytes,
        ...List.filled(BackupFileGateway.maxReadBytes - bytes.length, 32),
      ]);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'success', 'bytes': padded},
      );
      final old = state.session;
      expect(
        (await transfer.readCandidate()).status,
        BackupTransferStatus.candidate,
      );
      // Caller cancels confirmation by discarding the validated result.
      expect(state.session, same(old));
      expect(repo.saves, isEmpty);
    },
  );

  test('fresh state reloads restored data from real Safe Save files', () async {
    final directory = await Directory.systemTemp.createTemp('kmc_c3_');
    final repository = KeepMyCarRepository(
      IoLocalFileStorage(directory: () async => directory),
    );
    final original = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 10),
    );
    final restarted = PersistentPlanState(
      repository: repository,
      referenceMonth: const YearMonth(2026, 10),
    );
    try {
      await original.load();
      expect(original.phase, StartupPhase.noData);
      final production = BackupTransfer(state: original);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'success', 'bytes': bytes},
      );
      final read = await production.readCandidate();
      expect(
        (await production.restore(read.candidate!)).status,
        BackupTransferStatus.success,
      );
      original.dispose();
      await restarted.load();
      expect(restarted.phase, StartupPhase.ready);
      expect(codec.encode(restarted.snapshot, createdAt: time), bytes);
    } finally {
      restarted.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'missing Android connection is a platform error without mutation',
    () async {
      expect(
        (await transfer.readCandidate()).fileError,
        BackupFileError.platformFailure,
      );
      expect(repo.saves, isEmpty);
      expect(state.phase, StartupPhase.ready);
    },
  );

  test('disposed and unavailable states never start file operations', () async {
    var invocations = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      invocations++;
      return {'status': 'cancelled'};
    });
    for (final phase in [StartupPhase.loading, StartupPhase.uncertain]) {
      state.phase = phase;
      expect(
        (await transfer.readCandidate()).error,
        BackupTransferError.unavailable,
      );
      expect((await transfer.export()).error, BackupTransferError.unavailable);
    }
    state.phase = StartupPhase.noData;
    expect((await transfer.export()).error, BackupTransferError.unavailable);
    state.phase = StartupPhase.failure;
    expect((await transfer.export()).error, BackupTransferError.unavailable);
    state.dispose();
    expect(
      (await transfer.readCandidate()).error,
      BackupTransferError.unavailable,
    );
    expect(invocations, 0);
    // Replace it so the shared tearDown owns an undisposed notifier.
    await start(const NoData());
  });

  test(
    'selection has no timeout and duplicate operation is rejected',
    () async {
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (_) => pending.future);
      final request = transfer.readCandidate();
      expect((await transfer.export()).error, BackupTransferError.unavailable);
      pending.complete({'status': 'success', 'bytes': bytes});
      expect((await request).status, BackupTransferStatus.candidate);
    },
  );
}
