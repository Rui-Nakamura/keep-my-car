import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/backup/zip_backup_result.dart';
import 'package:keep_my_car/backup/zip_backup_worker.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';

import '../persistence_app_support.dart';
import '../photo/photo_test_support.dart';

class ProbeExpenses extends ListBase<PlannedExpense> {
  ProbeExpenses(this.values, this.port, this.label);
  final List<PlannedExpense> values;
  final SendPort port;
  final String label;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  PlannedExpense operator [](int index) => values[index];
  @override
  void operator []=(int index, PlannedExpense value) =>
      throw UnsupportedError('immutable');
  @override
  Iterator<PlannedExpense> get iterator {
    port.send((label, Isolate.current.hashCode));
    // Only this test worker pauses, allowing a concurrently started worker to
    // expose overlap. No timing/performance conclusion is inferred.
    sleep(const Duration(milliseconds: 25));
    return values.iterator;
  }
}

class ExplodingExpenses extends ListBase<PlannedExpense> {
  @override
  int get length => throw StateError('unexpected worker failure');
  @override
  set length(int value) => throw StateError('unused');
  @override
  PlannedExpense operator [](int index) => throw StateError('unused');
  @override
  void operator []=(int index, PlannedExpense value) =>
      throw StateError('unused');
}

RestoredCarData withExpenses(
  RestoredCarData data,
  List<PlannedExpense> expenses,
) => (
  photoId: data.photoId,
  ownerBirthMonth: data.ownerBirthMonth,
  car: data.car,
  planConditions: data.planConditions,
  plannedExpenses: expenses,
);

void main() {
  test(
    'real isolate round trip transfers candidate and immutable JPEG',
    () async {
      final worker = ZipBackupWorker();
      final data = sampleSnapshot();
      final photo = smallJpeg();
      final bytes = await worker.encode(data, jpeg: photo);
      final result = await worker.decode(bytes) as ZipBackupSuccess;
      expect(result.plan.car.name, data.car.name);
      expect(result.plan.planConditions, data.planConditions);
      expect(
        result.plan.plannedExpenses.map((e) => e.id),
        data.plannedExpenses.map((e) => e.id),
      );
      expect(result.jpeg, photo);
      expect(() => result.jpeg![0] = 0, throwsUnsupportedError);
      expect(() => result.plan.plannedExpenses.clear(), throwsUnsupportedError);
      bytes.fillRange(0, bytes.length, 0);
      expect(result.jpeg, photo);
    },
  );

  test(
    'known decode failure and encode exception cross worker boundary',
    () async {
      final worker = ZipBackupWorker();
      expect(
        (await worker.decode(Uint8List(0)) as ZipBackupFailure).issue,
        ZipBackupIssue.invalidZip,
      );
      await expectLater(
        worker.encode(sampleSnapshot(), jpeg: Uint8List(3 * 1024 * 1024 + 1)),
        throwsA(
          isA<ZipBackupFailure>().having(
            (e) => e.issue,
            'issue',
            ZipBackupIssue.sizeLimit,
          ),
        ),
      );
      expect(
        await worker.decode(await worker.encode(sampleSnapshot())),
        isA<ZipBackupSuccess>(),
      );
    },
  );

  test(
    'unexpected exception crosses actual isolate and queue remains usable',
    () async {
      final worker = ZipBackupWorker();
      await expectLater(
        worker.encode(withExpenses(sampleSnapshot(), ExplodingExpenses())),
        throwsA(isA<StateError>()),
      );
      expect(
        await worker.decode(await worker.encode(sampleSnapshot())),
        isA<ZipBackupSuccess>(),
      );
    },
  );

  test(
    'different worker instances serialize heavy work off the caller isolate',
    () async {
      final port = ReceivePort();
      final events = <(String, int)>[];
      final subscription = port.listen(
        (message) => events.add(message as (String, int)),
      );
      final data = sampleSnapshot();
      try {
        await Future.wait([
          ZipBackupWorker().encode(
            withExpenses(
              data,
              ProbeExpenses(data.plannedExpenses, port.sendPort, 'first'),
            ),
          ),
          ZipBackupWorker().encode(
            withExpenses(
              data,
              ProbeExpenses(data.plannedExpenses, port.sendPort, 'second'),
            ),
          ),
        ]);
        // The receive port can be delivered just after worker-result delivery.
        await Future<void>.delayed(Duration.zero);
        expect(events.map((e) => e.$1), containsAll(['first', 'second']));
        final firstSecond = events.indexWhere((e) => e.$1 == 'second');
        expect(events.skip(firstSecond).every((e) => e.$1 == 'second'), true);
        expect(events.every((e) => e.$2 != Isolate.current.hashCode), true);
      } finally {
        await subscription.cancel();
        port.close();
      }
    },
  );
}
