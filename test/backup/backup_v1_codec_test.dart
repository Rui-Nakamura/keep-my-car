import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/backup/backup_import_result.dart';
import 'package:keep_my_car/backup/backup_v1_codec.dart';
import 'package:keep_my_car/domain/models/car.dart';
import 'package:keep_my_car/domain/models/plan_conditions.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import '../plan_test_support.dart' show conditions;
import 'fixtures/backup_v1_fixture.dart';

const codec = BackupV1Codec();
final timestamp = DateTime.utc(2026, 10, 1, 1);
Map<String, dynamic> fixture() =>
    jsonDecode(backupV1Fixture) as Map<String, dynamic>;
Map<String, dynamic> data(Map<String, dynamic> root) =>
    root['data'] as Map<String, dynamic>;
Map<String, dynamic> section(Map<String, dynamic> root, String name) =>
    switch (name) {
      'data' => data(root),
      'expense' =>
        (data(root)['plannedExpenses'] as List).last as Map<String, dynamic>,
      _ => data(root)[name] as Map<String, dynamic>,
    };
BackupImportResult decode(Map<String, dynamic> root) =>
    codec.decode(utf8.encode(jsonEncode(root)));
void rejected(Map<String, dynamic> root, BackupImportIssue issue) => expect(
  decode(root),
  isA<BackupImportFailure>().having((r) => r.issue, 'issue', issue),
);

RestoredCarData inputs() => (
  ownerBirthMonth: const YearMonth(1970, 4),
  car: const Car(
    name: '愛車 🚗',
    firstRegistrationMonth: YearMonth(2018, 8),
    currentMileageKm: 45000,
    mileageCheckedMonth: YearMonth(2026, 9),
    annualMileageKm: 4000,
  ),
  planConditions: const PlanConditions(
    currentMileageKm: 45000,
    annualMileageKm: 4000,
    ownershipTargetAge: 70,
    currentCarFundYen: 500000,
    reserveTargetAge: 65,
    largeRepairReserveYen: 2000000,
  ),
  plannedExpenses: [
    const PlannedExpense(
      id: 17,
      name: 'タイヤ交換',
      amountYen: 80000,
      plannedMonth: YearMonth(2027, 4),
      basis: ExpenseBasis.quoted,
      memo: '見積もり確認済み 🚗',
      status: PlannedExpenseStatus.planned,
    ),
    const PlannedExpense(
      id: -3,
      name: '過去の予定',
      amountYen: 0,
      plannedMonth: YearMonth(2000, 1),
      basis: ExpenseBasis.selfEstimate,
      memo: null,
      status: PlannedExpenseStatus.completed,
    ),
    const PlannedExpense(
      id: 0,
      name: 'タイヤ交換',
      amountYen: 80000,
      plannedMonth: YearMonth(2027, 4),
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    ),
  ],
);

// Compare every formal field without relying on either serializer.
void expectInputs(RestoredCarData actual, RestoredCarData expected) {
  expect(actual.ownerBirthMonth, expected.ownerBirthMonth);
  expect(actual.car.name, expected.car.name);
  expect(
    actual.car.firstRegistrationMonth,
    expected.car.firstRegistrationMonth,
  );
  expect(actual.car.mileageCheckedMonth, expected.car.mileageCheckedMonth);
  expect(actual.car.currentMileageKm, expected.car.currentMileageKm);
  expect(actual.car.annualMileageKm, expected.car.annualMileageKm);
  expect(actual.planConditions, expected.planConditions);
  expect(actual.plannedExpenses.length, expected.plannedExpenses.length);
  for (var i = 0; i < expected.plannedExpenses.length; i++) {
    final a = actual.plannedExpenses[i];
    final e = expected.plannedExpenses[i];
    expect(
      [a.id, a.name, a.amountYen, a.plannedMonth, a.basis, a.memo, a.status],
      [e.id, e.name, e.amountYen, e.plannedMonth, e.basis, e.memo, e.status],
    );
  }
}

void main() {
  for (final date in [
    '2024-02-29T23:59:59+09:00',
    '2000-02-29T00:00:00-12:00',
    '2026-01-01T00:00:00+14:00',
    '20261001T100000+0900',
    '2026-10-01T24:00:00Z',
  ]) {
    test('valid calendar timestamp $date', () {
      expect(
        decode(fixture()..['createdAt'] = date),
        isA<BackupImportSuccess>(),
      );
    });
  }
  for (final date in [
    '2026-00-01T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-01-00T00:00:00Z',
    '2026-01-32T00:00:00Z',
    '2026-04-31T00:00:00Z',
    '2026-02-29T00:00:00Z',
    '1900-02-29T00:00:00Z',
    '2024-02-30T00:00:00+09:00',
    '2026-10-01T25:00:00Z',
    '2026-10-01T24:00:01Z',
    '2026-10-01T24:00:00.1Z',
    '2026-10-01T10:60:00Z',
    '2026-10-01T10:00:99Z',
    '2026-10-01T10:00:00+99:00',
    '2026-10-01T10:00:00+09:99',
    '2026-1001T10:00:00Z',
    '2026-10-01T10:0000Z',
  ]) {
    test('timestamp overflow rejected: $date', () {
      rejected(
        fixture()..['createdAt'] = date,
        BackupImportIssue.invalidStructure,
      );
    });
  }
  test('export matches independent v1 fixture including exact field set', () {
    expect(
      jsonDecode(utf8.decode(codec.encode(inputs(), createdAt: timestamp))),
      fixture(),
    );
  });
  test(
    'independent fixture imports every field, original order and metadata',
    () {
      final result =
          codec.decode(utf8.encode(backupV1Fixture)) as BackupImportSuccess;
      expectInputs(result.data, inputs());
      expect(() => result.data.plannedExpenses.clear(), throwsUnsupportedError);
    },
  );
  test(
    'UTF-8 Japanese round trip is deterministic and leaves input unchanged',
    () {
      final source = inputs();
      final bytes = codec.encode(source, createdAt: timestamp);
      expect(codec.encode(source, createdAt: timestamp), bytes);
      expect(utf8.decode(bytes), contains('見積もり確認済み 🚗'));
      expectInputs((codec.decode(bytes) as BackupImportSuccess).data, source);
      expectInputs(source, inputs());
    },
  );
  test('empty expenses round trip', () {
    final source = inputs();
    final empty = (
      ownerBirthMonth: source.ownerBirthMonth,
      car: source.car,
      planConditions: source.planConditions,
      plannedExpenses: <PlannedExpense>[],
    );
    expectInputs(
      (codec.decode(
        codec.encode(empty, createdAt: timestamp),
      ) as BackupImportSuccess).data,
      empty,
    );
  });
  test('Golden Sample retains all formal inputs', () {
    final source = (
      ownerBirthMonth: goldenSample.owner.birthMonth,
      car: goldenSample.car,
      planConditions: conditions(),
      plannedExpenses: goldenSample.plannedExpenses,
    );
    expectInputs(
      (codec.decode(
        codec.encode(source, createdAt: timestamp),
      ) as BackupImportSuccess).data,
      source,
    );
  });
  for (final date in [
    '1900-01-01T00:00:00Z',
    '9999-12-31T23:59:59Z',
    '2026-10-01T10:00:00+09:00',
  ]) {
    test('createdAt $date is metadata only', () {
      final root = fixture()..['createdAt'] = date;
      expectInputs((decode(root) as BackupImportSuccess).data, inputs());
    });
  }
  for (final field in ['format', 'exportFormatVersion', 'createdAt', 'data']) {
    final issue = field == 'format'
        ? BackupImportIssue.notBackup
        : BackupImportIssue.invalidStructure;
    test(
      'missing envelope $field',
      () => rejected(fixture()..remove(field), issue),
    );
    for (final value in [null, true, [], 1.0]) {
      test(
        'invalid envelope $field = $value',
        () => rejected(fixture()..[field] = value, issue),
      );
    }
  }
  test(
    'foreign format',
    () =>
        rejected(fixture()..['format'] = 'other', BackupImportIssue.notBackup),
  );
  test(
    'string version',
    () => rejected(
      fixture()..['exportFormatVersion'] = '1',
      BackupImportIssue.invalidStructure,
    ),
  );
  for (final version in [-1, 0, 2, 999]) {
    test(
      'unsupported version $version',
      () => rejected(
        fixture()..['exportFormatVersion'] = version,
        BackupImportIssue.unsupportedVersion,
      ),
    );
  }
  for (final date in ['', 'not-a-date', '2026/10/01', '2026-99-99']) {
    test(
      'invalid createdAt $date',
      () => rejected(
        fixture()..['createdAt'] = date,
        BackupImportIssue.invalidStructure,
      ),
    );
  }
  for (final bytes in [
    utf8.encode('{'),
    utf8.encode('null'),
    utf8.encode('[]'),
    utf8.encode('42'),
    [0xff],
  ]) {
    test('invalid UTF-8 / JSON / root $bytes', () {
      expect(
        codec.decode(bytes),
        isA<BackupImportFailure>().having(
          (r) => r.issue,
          'issue',
          BackupImportIssue.invalidStructure,
        ),
      );
    });
  }

  for (final name in ['data', 'car', 'planConditions', 'expense']) {
    for (final entry in section(fixture(), name).entries) {
      test('missing $name.${entry.key}', () {
        final root = fixture();
        section(root, name).remove(entry.key);
        rejected(root, BackupImportIssue.invalidStructure);
      });
      test('wrong type $name.${entry.key}', () {
        final root = fixture();
        section(root, name)[entry.key] = true;
        rejected(root, BackupImportIssue.invalidStructure);
      });
    }
  }
  for (final entry in <(String, String, Object?)>[
    ('data', 'ownerBirthMonth', '１９７０-04'),
    ('car', 'firstRegistrationMonth', '2018-13'),
    ('car', 'mileageCheckedMonth', '2026-9'),
    ('expense', 'plannedMonth', '2027-04-01'),
    ('expense', 'basis', 'unknown'),
    ('expense', 'status', 'unknown'),
    ('car', 'name', '   '),
    ('car', 'name', '\t愛車'),
    ('car', 'name', 'あ' * 41),
    ('expense', 'name', '   '),
    ('expense', 'amountYen', -1),
    ('expense', 'amountYen', 1000000001),
    ('expense', 'id', 17),
    ('car', 'currentMileageKm', 45001),
    ('car', 'annualMileageKm', 4001),
    ('planConditions', 'currentMileageKm', 2000001),
    ('planConditions', 'annualMileageKm', 200001),
    ('planConditions', 'currentCarFundYen', -1),
    ('planConditions', 'largeRepairReserveYen', 1000000001),
    ('planConditions', 'ownershipTargetAge', 101),
    ('planConditions', 'reserveTargetAge', 71),
  ]) {
    test(
      'existing content validation rejects $entry without partial result',
      () {
        final root = fixture();
        section(root, entry.$1)[entry.$2] = entry.$3;
        rejected(root, BackupImportIssue.invalidContent);
      },
    );
  }
  for (final entry in [
    ('expense', 'id'),
    ('expense', 'amountYen'),
    ('planConditions', 'ownershipTargetAge'),
  ]) {
    test('JSON double is not integer: $entry', () {
      final root = fixture();
      section(root, entry.$1)[entry.$2] = 1.0;
      rejected(root, BackupImportIssue.invalidStructure);
    });
  }
  test('invalid array element rejects whole payload', () {
    final root = fixture();
    (data(root)['plannedExpenses'] as List).add(null);
    rejected(root, BackupImportIssue.invalidStructure);
  });
  for (final name in ['envelope', 'data', 'car', 'planConditions', 'expense']) {
    test('unknown fields ignored at $name and never re-exported', () {
      final root = fixture();
      final target = name == 'envelope' ? root : section(root, name);
      for (final key in [
        'formatVersion',
        'nextId',
        'referenceMonth',
        'futureTimeline',
        'repairReserve',
        'pending',
        'diff',
        'draft',
        'uiState',
        'androidPath',
        'uri',
        'platform',
      ]) {
        target[key] = {'unknown': true};
      }
      final candidate = (decode(root) as BackupImportSuccess).data;
      expectInputs(candidate, inputs());
      expect(
        jsonDecode(utf8.decode(codec.encode(candidate, createdAt: timestamp))),
        fixture(),
      );
    });
  }
  test(
    'past targets, future birth month, out-of-period expenses remain valid',
    () {
      final root = fixture();
      data(root)['ownerBirthMonth'] = '2200-01';
      section(root, 'planConditions')['ownershipTargetAge'] = 0;
      section(root, 'planConditions')['reserveTargetAge'] = 0;
      expect(decode(root), isA<BackupImportSuccess>());
      data(root)['ownerBirthMonth'] = '1800-01';
      expect(decode(root), isA<BackupImportSuccess>());
    },
  );
  for (final invalid in [
    'name',
    'mileage',
    'duplicateId',
    'month',
    'expenseAmount',
  ]) {
    test('export cannot bypass mapper validation: $invalid', () {
      final source = inputs();
      final candidate = (
        ownerBirthMonth: invalid == 'month'
            ? const YearMonth(10000, 1)
            : source.ownerBirthMonth,
        car: invalid == 'name'
            ? source.car.copyWith(name: '\t愛車')
            : invalid == 'mileage'
            ? source.car.copyWith(currentMileageKm: 1)
            : source.car,
        planConditions: source.planConditions,
        plannedExpenses: invalid == 'duplicateId'
            ? [source.plannedExpenses.first, source.plannedExpenses.first]
            : invalid == 'expenseAmount'
            ? [
                const PlannedExpense(
                  id: 1,
                  name: '不正',
                  amountYen: -1,
                  plannedMonth: YearMonth(2027, 1),
                  basis: ExpenseBasis.placeholder,
                  memo: null,
                  status: PlannedExpenseStatus.planned,
                ),
              ]
            : source.plannedExpenses,
      );
      expect(
        () => codec.encode(candidate, createdAt: timestamp),
        invalid == 'month' ? throwsFormatException : throwsArgumentError,
      );
    });
  }
}
