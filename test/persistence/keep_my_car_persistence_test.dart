import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/planned_expense.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/plan_conditions_validation.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/features/timeline/future_timeline_calculator.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_dto.dart';
import 'package:keep_my_car/persistence/keep_my_car_data_mapper.dart';
import 'package:keep_my_car/persistence/keep_my_car_json_codec.dart';
import 'package:keep_my_car/persistence/keep_my_car_payload_codec.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import '../plan_test_support.dart' show conditions;

const codec = KeepMyCarJsonCodec();
const mapper = KeepMyCarDataMapper();

// Independent wire fixture: decoder expectations do not depend on the encoder.
Map<String, dynamic> wire() => {
  'formatVersion': 1,
  'ownerBirthMonth': '1970-04',
  'car': <String, dynamic>{
    'name': 'メルセデスAMG E53',
    'firstRegistrationMonth': '2018-08',
    'currentMileageKm': 45000,
    'mileageCheckedMonth': '2026-09',
    'annualMileageKm': 4000,
  },
  'planConditions': <String, dynamic>{
    'currentMileageKm': 45000,
    'annualMileageKm': 4000,
    'ownershipTargetAge': 70,
    'currentCarFundYen': 500000,
    'reserveTargetAge': 65,
    'largeRepairReserveYen': 2000000,
  },
  'plannedExpenses': <dynamic>[
    <String, dynamic>{
      'id': 17,
      'name': 'タイヤ交換',
      'amountYen': 80000,
      'plannedMonth': '2027-04',
      'basis': 'quoted',
      'memo': '見積もり確認済み 🚗',
      'status': 'planned',
    },
    <String, dynamic>{
      'id': 3,
      'name': 'バッテリー交換',
      'amountYen': 0,
      'plannedMonth': '2026-09',
      'basis': 'selfEstimate',
      'memo': null,
      'status': 'completed',
    },
  ],
};

Map<String, dynamic> section(Map<String, dynamic> data, String name) =>
    switch (name) {
      'root' => data,
      'expense' =>
        (data['plannedExpenses'] as List).first as Map<String, dynamic>,
      _ => data[name] as Map<String, dynamic>,
    };

KeepMyCarDataDto sampleDto({List<PlannedExpense>? expenses}) => mapper.toDto(
  ownerBirthMonth: goldenSample.owner.birthMonth,
  car: goldenSample.car,
  planConditions: conditions(),
  plannedExpenses: expenses ?? goldenSample.plannedExpenses,
);

void expectSample(RestoredCarData actual) {
  expect(actual.ownerBirthMonth, const YearMonth(1970, 4));
  final car = goldenSample.car;
  expect(actual.car.name, car.name);
  expect(actual.car.firstRegistrationMonth, car.firstRegistrationMonth);
  expect(actual.car.currentMileageKm, car.currentMileageKm);
  expect(actual.car.mileageCheckedMonth, car.mileageCheckedMonth);
  expect(actual.car.annualMileageKm, car.annualMileageKm);
  expect(actual.planConditions, conditions());
  expect(
    actual.plannedExpenses,
    hasLength(goldenSample.plannedExpenses.length),
  );
  for (var i = 0; i < actual.plannedExpenses.length; i++) {
    final a = actual.plannedExpenses[i];
    final e = goldenSample.plannedExpenses[i];
    expect(a.id, e.id);
    expect(a.name, e.name);
    expect(a.plannedMonth, e.plannedMonth);
    expect(a.amountYen, e.amountYen);
    expect(a.basis, e.basis);
    expect(a.memo, e.memo);
    expect(a.status, e.status);
  }
}

void main() {
  for (final month in [
    const YearMonth(1970, 4),
    const YearMonth(2000, 1),
    const YearMonth(2000, 12),
    const YearMonth(2200, 1),
    const YearMonth(1800, 1),
  ]) {
    test(
      'ownerBirthMonth $month survives without new age or current-month rules',
      () {
        final dto = mapper.toDto(
          ownerBirthMonth: month,
          car: goldenSample.car,
          planConditions: conditions(),
          plannedExpenses: goldenSample.plannedExpenses,
        );
        expect(dto.ownerBirthMonth, month.toString());
        final json = jsonDecode(codec.encode(dto)) as Map<String, dynamic>;
        expect(json['ownerBirthMonth'], month.toString());
        expect(json['formatVersion'], 1);
        expect(json.containsKey('referenceMonth'), isFalse);
        final restored = mapper.toDomain(codec.decode(jsonEncode(json)));
        expect(restored.ownerBirthMonth, month);
      },
    );
  }
  for (final invalid in ['1970-00', '1970-13', '70-04', '1970/04']) {
    test('ownerBirthMonth rejects $invalid', () {
      final data = wire()..['ownerBirthMonth'] = invalid;
      expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
    });
  }
  test('manual DTO ownerBirthMonth cannot bypass validation', () {
    final source = sampleDto();
    final invalid = KeepMyCarDataDto(
      ownerBirthMonth: '1970-13',
      car: source.car,
      planConditions: source.planConditions,
      plannedExpenses: source.plannedExpenses,
    );
    expect(() => codec.encode(invalid), throwsFormatException);
    expect(() => mapper.toDomain(invalid), throwsFormatException);
  });
  for (final age in [0, 100]) {
    test('fixed age boundary $age survives full persistence round trip', () {
      final plan = conditions(ownership: age, age: age);
      final dto = mapper.toDto(
        ownerBirthMonth: goldenSample.owner.birthMonth,
        car: goldenSample.car,
        planConditions: plan,
        plannedExpenses: goldenSample.plannedExpenses,
      );
      final restored = mapper.toDomain(codec.decode(codec.encode(dto)));
      expect(restored.planConditions, plan);
      expect(
        restored.plannedExpenses,
        hasLength(goldenSample.plannedExpenses.length),
      );
    });
  }
  for (final field in ['ownershipTargetAge', 'reserveTargetAge']) {
    for (final age in [-1, 101]) {
      test('$field $age is rejected in both persistence directions', () {
        final data = wire();
        section(data, 'planConditions')[field] = age;
        expect(
          () => mapper.toDomain(codec.decode(jsonEncode(data))),
          throwsArgumentError,
        );
        final plan = field == 'ownershipTargetAge'
            ? conditions(ownership: age)
            : conditions(age: age);
        expect(
          () => mapper.toDto(
            ownerBirthMonth: goldenSample.owner.birthMonth,
            car: goldenSample.car,
            planConditions: plan,
            plannedExpenses: [],
          ),
          throwsArgumentError,
        );
      });
    }
  }
  test('Domain to DTO preserves all fields and stable enum identifiers', () {
    final dto = sampleDto();
    expect(dto.formatVersion, 1);
    expect(dto.ownerBirthMonth, '1970-04');
    expect(dto.car.name, 'メルセデスAMG E53');
    expect(dto.car.firstRegistrationMonth, '2018-08');
    expect(dto.car.mileageCheckedMonth, '2026-09');
    expect(dto.car.currentMileageKm, 45000);
    expect(dto.car.annualMileageKm, 4000);
    expect(dto.planConditions.currentMileageKm, 45000);
    expect(dto.planConditions.annualMileageKm, 4000);
    expect(dto.planConditions.ownershipTargetAge, 70);
    expect(dto.planConditions.currentCarFundYen, 500000);
    expect(dto.planConditions.reserveTargetAge, 65);
    expect(dto.planConditions.largeRepairReserveYen, 2000000);
    for (var i = 0; i < dto.plannedExpenses.length; i++) {
      final a = dto.plannedExpenses[i];
      final e = goldenSample.plannedExpenses[i];
      expect(a.id, e.id);
      expect(a.name, e.name);
      expect(a.amountYen, e.amountYen);
      expect(a.plannedMonth, e.plannedMonth.toString());
      expect(a.basis, 'placeholder');
      expect(a.status, 'planned');
      expect(a.memo, isNull);
    }
  });

  test('DTO to Domain restores every Golden Sample field', () {
    expectSample(mapper.toDomain(sampleDto()));
  });

  test('independent JSON fixture decodes to DTO', () {
    final dto = codec.decode(jsonEncode(wire()));
    expect(dto.formatVersion, 1);
    expect(dto.car.name, 'メルセデスAMG E53');
    expect(dto.car.firstRegistrationMonth, '2018-08');
    expect(dto.car.mileageCheckedMonth, '2026-09');
    expect(dto.plannedExpenses.map((e) => e.id), [17, 3]);
    expect(dto.plannedExpenses.first.name, 'タイヤ交換');
    expect(dto.plannedExpenses.last.amountYen, 0);
    expect(dto.plannedExpenses.first.memo, '見積もり確認済み 🚗');
    expect(dto.plannedExpenses.last.memo, isNull);
  });

  test('DTO encodes to exact logical JSON schema', () {
    expect(jsonDecode(codec.encode(codec.decode(jsonEncode(wire())))), wire());
  });

  test('internal encoding preserves exact fixture bytes and field order', () {
    final source = jsonEncode(wire());
    expect(
      utf8.encode(codec.encode(codec.decode(source))),
      utf8.encode(source),
    );
  });

  test('payload round trip needs no version and emits only input fields', () {
    const payload = KeepMyCarPayloadCodec();
    final expected = wire()..remove('formatVersion');
    final dto = payload.decode(expected);
    expect(dto.formatVersion, 1);
    expect(payload.encode(dto), expected);
    expect(payload.encode(dto).keys, [
      'ownerBirthMonth',
      'car',
      'planConditions',
      'plannedExpenses',
    ]);
    expect(codec.encode(dto), jsonEncode(wire()));
  });

  test('payload does not interpret unknown version metadata', () {
    const payload = KeepMyCarPayloadCodec();
    final expected = wire()..remove('formatVersion');
    final input = {...expected, 'formatVersion': 'not payload metadata'};
    final dto = payload.decode(input);
    expect(dto.formatVersion, 1);
    expect(payload.encode(dto), expected);
    expect(input['formatVersion'], 'not payload metadata');
    expect(() => codec.decode(jsonEncode(input)), throwsFormatException);
  });

  test(
    'Domain JSON UTF-8 Domain round trip preserves Japanese and all values',
    () {
      final bytes = utf8.encode(codec.encode(sampleDto()));
      expectSample(mapper.toDomain(codec.decode(utf8.decode(bytes))));
    },
  );

  test('empty expenses remain distinct from a zero-yen expense', () {
    final empty = mapper.toDomain(
      codec.decode(codec.encode(sampleDto(expenses: []))),
    );
    expect(empty.plannedExpenses, isEmpty);
    final data = wire();
    data['plannedExpenses'] = [(data['plannedExpenses'] as List).last];
    final zero = mapper.toDomain(codec.decode(jsonEncode(data)));
    expect(zero.plannedExpenses, hasLength(1));
    expect(zero.plannedExpenses.single.amountYen, 0);
  });

  test('all enum identifiers and nullable/non-null memo survive mapping', () {
    for (final basis in ExpenseBasis.values) {
      for (final status in PlannedExpenseStatus.values) {
        for (final memo in <String?>[null, '', '整備記録 🚗']) {
          final expense = PlannedExpense(
            id: 93,
            name: '点検',
            plannedMonth: const YearMonth(2027, 1),
            amountYen: 0,
            basis: basis,
            memo: memo,
            status: status,
          );
          final restored = mapper.toDomain(
            codec.decode(codec.encode(sampleDto(expenses: [expense]))),
          );
          expect(restored.plannedExpenses.single.basis, basis);
          expect(restored.plannedExpenses.single.status, status);
          expect(restored.plannedExpenses.single.memo, memo);
        }
      }
    }
  });

  for (final entry in {
    'root': [
      'ownerBirthMonth',
      'formatVersion',
      'car',
      'planConditions',
      'plannedExpenses',
    ],
    'car': [
      'name',
      'firstRegistrationMonth',
      'currentMileageKm',
      'mileageCheckedMonth',
      'annualMileageKm',
    ],
    'planConditions': [
      'currentMileageKm',
      'annualMileageKm',
      'ownershipTargetAge',
      'currentCarFundYen',
      'reserveTargetAge',
      'largeRepairReserveYen',
    ],
    'expense': [
      'id',
      'name',
      'amountYen',
      'plannedMonth',
      'basis',
      'memo',
      'status',
    ],
  }.entries) {
    for (final field in entry.value) {
      test('${entry.key}.$field missing is rejected', () {
        final data = wire();
        section(data, entry.key).remove(field);
        expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
      });
      if (field != 'memo') {
        test('${entry.key}.$field null is rejected', () {
          final data = wire();
          section(data, entry.key)[field] = null;
          expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
        });
      }
      test('${entry.key}.$field wrong JSON type is rejected', () {
        final data = wire();
        final object = section(data, entry.key);
        object[field] = object[field] is String ? 123 : 'invalid';
        expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
      });
    }
  }

  for (final version in [-1, 0, 2, 999, 1.0, true]) {
    test(
      'unsupported or non-integer version $version (${version.runtimeType}) fails',
      () {
        final data = wire()..['formatVersion'] = version;
        expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
      },
    );
  }

  for (final source in [
    '',
    '{',
    '{"formatVersion":1,}',
    'null',
    '[]',
    '1',
    'true',
    '"text"',
  ]) {
    test('invalid syntax or root: $source', () {
      expect(() => codec.decode(source), throwsFormatException);
    });
  }

  for (final location in [
    ('root', 'ownerBirthMonth'),
    ('car', 'firstRegistrationMonth'),
    ('car', 'mileageCheckedMonth'),
    ('expense', 'plannedMonth'),
  ]) {
    for (final month in [
      '2026-00',
      '2026-13',
      '26-09',
      '2026/09',
      '',
      '2026-09-01',
      '2026-09T00:00:00Z',
      '2026-09\n',
      ' 2026-09',
      '10000-01',
      null,
      202609,
    ]) {
      test('${location.$2} rejects invalid month $month', () {
        final data = wire();
        section(data, location.$1)[location.$2] = month;
        expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
      });
    }
  }

  for (final entry in {
    'car': ['currentMileageKm', 'annualMileageKm'],
    'planConditions': [
      'currentMileageKm',
      'annualMileageKm',
      'ownershipTargetAge',
      'currentCarFundYen',
      'reserveTargetAge',
      'largeRepairReserveYen',
    ],
    'expense': ['id', 'amountYen'],
  }.entries) {
    for (final field in entry.value) {
      for (final invalid in [1.0, 1.5, true]) {
        test(
          '${entry.key}.$field rejects $invalid (${invalid.runtimeType})',
          () {
            final data = wire();
            section(data, entry.key)[field] = invalid;
            expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
          },
        );
      }
    }
  }

  for (final field in ['basis', 'status']) {
    test('unknown $field identifier is rejected', () {
      final data = wire();
      section(data, 'expense')[field] = 'futureValue';
      expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
    });
  }

  test(
    'unknown fields at every level are ignored, object order is irrelevant',
    () {
      final data = wire();
      for (final name in ['root', 'car', 'planConditions', 'expense']) {
        section(data, name)['futureField'] = {
          'nested': [null, true, 3],
        };
      }
      Object? reverse(Object? value) {
        if (value is Map<String, dynamic>) {
          return {
            for (final key in value.keys.toList().reversed)
              key: reverse(value[key]),
          };
        }
        if (value is List) return value.map(reverse).toList();
        return value;
      }

      final decoded = codec.decode(jsonEncode(reverse(data)));
      expect(jsonDecode(codec.encode(decoded)), wire());
    },
  );

  for (final item in [null, 1, 'expense', [], true]) {
    test('invalid later expense $item fails the entire decode', () {
      final data = wire();
      (data['plannedExpenses'] as List).add(item);
      expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
    });
  }

  for (final invalid in [
    ('car', 'name', ''),
    ('car', 'name', '　 '),
    ('car', 'name', '車' * 41),
    ('car', 'name', '\r愛車'),
    ('car', 'name', '愛車\n'),
    ('car', 'name', '\t愛車'),
    ('car', 'currentMileageKm', -1),
    ('car', 'annualMileageKm', 200001),
    ('planConditions', 'currentMileageKm', 2000001),
    ('planConditions', 'annualMileageKm', -1),
    ('planConditions', 'ownershipTargetAge', 101),
    ('planConditions', 'ownershipTargetAge', 55),
    ('planConditions', 'currentCarFundYen', -1),
    ('planConditions', 'reserveTargetAge', 71),
    ('planConditions', 'largeRepairReserveYen', 1000000001),
    ('expense', 'name', '　 '),
    ('expense', 'name', '費' * 41),
    ('expense', 'amountYen', -1),
    ('expense', 'amountYen', 1000000001),
  ]) {
    test(
      'existing domain validation rejects $invalid after structural decode',
      () {
        final data = wire();
        section(data, invalid.$1)[invalid.$2] = invalid.$3;
        final dto = codec.decode(jsonEncode(data));
        expect(() => mapper.toDomain(dto), throwsArgumentError);
      },
    );
  }

  test('domain to DTO also rejects invalid domain input', () {
    expect(
      () => mapper.toDto(
        ownerBirthMonth: goldenSample.owner.birthMonth,
        car: goldenSample.car.copyWith(name: '\t愛車'),
        planConditions: conditions(),
        plannedExpenses: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => mapper.toDto(
        ownerBirthMonth: goldenSample.owner.birthMonth,
        car: goldenSample.car,
        planConditions: conditions(fund: -1),
        plannedExpenses: [],
      ),
      throwsArgumentError,
    );
    final invalid = PlannedExpense(
      id: 1,
      name: '',
      plannedMonth: const YearMonth(2027, 1),
      amountYen: -1,
      basis: ExpenseBasis.placeholder,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );
    expect(() => sampleDto(expenses: [invalid]), throwsArgumentError);
  });

  for (final laterMonth in [
    const YearMonth(2036, 9),
    const YearMonth(2041, 9),
  ]) {
    test(
      'saved plan restores, saves and restores again at $laterMonth while editing rejects it',
      () {
        final plan = conditions();
        expect(
          validatePlanConditions(
            plan,
            birthMonth: const YearMonth(1970, 4),
            referenceMonth: const YearMonth(2026, 9),
          ),
          isEmpty,
        );
        final saved = codec.encode(sampleDto());
        const laterMapper = KeepMyCarDataMapper();
        final restored = laterMapper.toDomain(codec.decode(saved));
        expectSample(restored);
        final savedAgain = codec.encode(
          laterMapper.toDto(
            ownerBirthMonth: goldenSample.owner.birthMonth,
            car: restored.car,
            planConditions: restored.planConditions,
            plannedExpenses: restored.plannedExpenses,
          ),
        );
        expect(jsonDecode(savedAgain), jsonDecode(saved));
        expectSample(laterMapper.toDomain(codec.decode(savedAgain)));
        final editingErrors = validatePlanConditions(
          restored.planConditions,
          birthMonth: const YearMonth(1970, 4),
          referenceMonth: laterMonth,
        );
        expect(
          editingErrors[PlanField.reserveAge],
          PlanInputError.pastTargetMonth,
        );
        expect(
          editingErrors[PlanField.ownershipAge],
          laterMonth.year == 2041 ? PlanInputError.outOfRange : isNull,
        );
      },
    );
  }

  test('past reserve target alone is not storage corruption', () {
    final data = wire();
    section(data, 'planConditions')['reserveTargetAge'] = 55;
    final restored = mapper.toDomain(codec.decode(jsonEncode(data)));
    expect(restored.planConditions.reserveTargetAge, 55);
    expect(
      validatePlanConditions(
        restored.planConditions,
        birthMonth: const YearMonth(1970, 4),
        referenceMonth: const YearMonth(2026, 9),
      )[PlanField.reserveAge],
      PlanInputError.pastTargetMonth,
    );
  });

  for (final field in ['currentMileageKm', 'annualMileageKm']) {
    test(
      '$field mismatch rejects the whole snapshot without synchronization',
      () {
        final data = wire();
        section(data, 'car')[field] = (section(data, 'car')[field] as int) + 1;
        final dto = codec.decode(jsonEncode(data));
        final before = codec.encode(dto);
        expect(() => mapper.toDomain(dto), throwsArgumentError);
        expect(codec.encode(dto), before);
        final car = goldenSample.car.copyWith(
          currentMileageKm: field == 'currentMileageKm' ? 45001 : 45000,
          annualMileageKm: field == 'annualMileageKm' ? 4001 : 4000,
        );
        expect(
          () => mapper.toDto(
            ownerBirthMonth: goldenSample.owner.birthMonth,
            car: car,
            planConditions: conditions(),
            plannedExpenses: [],
          ),
          throwsArgumentError,
        );
      },
    );
  }

  test('matching snapshot mileage restores both values without changes', () {
    final restored = mapper.toDomain(codec.decode(jsonEncode(wire())));
    expect(restored.car.currentMileageKm, 45000);
    expect(restored.planConditions.currentMileageKm, 45000);
    expect(restored.car.annualMileageKm, 4000);
    expect(restored.planConditions.annualMileageKm, 4000);
  });

  test('exact domain upper limits survive Domain JSON Domain round trip', () {
    final plan = conditions(
      mileage: 2000000,
      annual: 200000,
      ownership: 100,
      age: 100,
    );
    final car = goldenSample.car.copyWith(
      currentMileageKm: 2000000,
      annualMileageKm: 200000,
    );
    final expense = PlannedExpense(
      id: 1,
      name: '🚗' * 40,
      plannedMonth: const YearMonth(2070, 4),
      amountYen: 1000000000,
      basis: ExpenseBasis.quoted,
      memo: null,
      status: PlannedExpenseStatus.planned,
    );
    expect(expense.name.runes.length, 40);
    final restored = mapper.toDomain(
      codec.decode(
        codec.encode(
          mapper.toDto(
            ownerBirthMonth: goldenSample.owner.birthMonth,
            car: car,
            planConditions: plan,
            plannedExpenses: [expense],
          ),
        ),
      ),
    );
    expect(restored.planConditions, plan);
    expect(restored.car.currentMileageKm, 2000000);
    expect(restored.car.annualMileageKm, 200000);
    expect(restored.planConditions.ownershipTargetAge, 100);
    expect(restored.planConditions.reserveTargetAge, 100);
    expect(restored.plannedExpenses.single.name, expense.name);
    expect(restored.plannedExpenses.single.amountYen, 1000000000);
  });

  test(
    'fixed plan rules still reject old snapshots at a later reference month',
    () {
      const laterMapper = KeepMyCarDataMapper();
      for (final invalid in [
        ('ownershipTargetAge', 101),
        ('reserveTargetAge', 71),
        ('currentCarFundYen', -1),
        ('largeRepairReserveYen', 1000000001),
      ]) {
        final data = wire();
        section(data, 'planConditions')[invalid.$1] = invalid.$2;
        expect(
          () => laterMapper.toDomain(codec.decode(jsonEncode(data))),
          throwsArgumentError,
        );
      }
    },
  );

  test('normalization and Unicode limits reuse domain rules', () {
    final data = wire();
    section(data, 'car')['name'] = '  ${'🚗' * 40}　';
    section(data, 'expense')['name'] = '  タイヤ　交換  ';
    final restored = mapper.toDomain(codec.decode(jsonEncode(data)));
    expect(restored.car.name, '🚗' * 40);
    expect(restored.plannedExpenses.first.name, 'タイヤ　交換');
    final dto = mapper.toDto(
      ownerBirthMonth: goldenSample.owner.birthMonth,
      car: goldenSample.car.copyWith(name: ' 愛車　A '),
      planConditions: conditions(),
      plannedExpenses: [],
    );
    expect(dto.car.name, '愛車　A');
  });

  test(
    'out-of-period expenses and duplicate contents with distinct IDs survive',
    () {
      final data = wire();
      final first = section(data, 'expense');
      first['plannedMonth'] = '2045-04';
      data['plannedExpenses'] = [
        first,
        {...first, 'id': 18},
        {...first, 'id': 19, 'plannedMonth': '2020-01'},
      ];
      final restored = mapper.toDomain(codec.decode(jsonEncode(data)));
      expect(restored.plannedExpenses.map((e) => e.id), [17, 18, 19]);
      expect(restored.plannedExpenses.map((e) => e.plannedMonth.year), [
        2045,
        2045,
        2020,
      ]);
      expect(
        jsonDecode(
          codec.encode(
            mapper.toDto(
              ownerBirthMonth: goldenSample.owner.birthMonth,
              car: restored.car,
              planConditions: restored.planConditions,
              plannedExpenses: restored.plannedExpenses,
            ),
          ),
        ),
        data,
      );
    },
  );

  test(
    'duplicate IDs reject restoration and serialization without renumbering',
    () {
      final data = wire();
      (data['plannedExpenses'] as List).last['id'] = 17;
      expect(
        () => mapper.toDomain(codec.decode(jsonEncode(data))),
        throwsArgumentError,
      );
      expect(
        () => sampleDto(
          expenses: [
            goldenSample.plannedExpenses.first,
            goldenSample.plannedExpenses.first,
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'a later domain error returns no partial aggregate or input mutation',
    () {
      final data = wire();
      (data['plannedExpenses'] as List).last['amountYen'] = -1;
      final dto = codec.decode(jsonEncode(data));
      final before = codec.encode(dto);
      expect(() => mapper.toDomain(dto), throwsArgumentError);
      expect(codec.encode(dto), before);
    },
  );

  test('DTO and restored lists are immutable snapshots', () {
    final source = sampleDto();
    final list = source.plannedExpenses.toList();
    final dto = KeepMyCarDataDto(
      ownerBirthMonth: goldenSample.owner.birthMonth.toString(),
      car: source.car,
      planConditions: source.planConditions,
      plannedExpenses: list,
    );
    list.clear();
    expect(dto.plannedExpenses, hasLength(6));
    expect(() => dto.plannedExpenses.clear(), throwsUnsupportedError);
    expect(
      () => mapper.toDomain(dto).plannedExpenses.clear(),
      throwsUnsupportedError,
    );
  });

  test('manually constructed invalid DTO cannot bypass format checks', () {
    final source = sampleDto();
    final invalidVersion = KeepMyCarDataDto(
      formatVersion: 2,
      ownerBirthMonth: goldenSample.owner.birthMonth.toString(),
      car: source.car,
      planConditions: source.planConditions,
      plannedExpenses: [],
    );
    final invalidMonth = KeepMyCarDataDto(
      ownerBirthMonth: goldenSample.owner.birthMonth.toString(),
      car: CarDto(
        name: '愛車',
        firstRegistrationMonth: '2026-13',
        currentMileageKm: 0,
        mileageCheckedMonth: '2026-09',
        annualMileageKm: 0,
      ),
      planConditions: source.planConditions,
      plannedExpenses: [],
    );
    for (final dto in [invalidVersion, invalidMonth]) {
      expect(() => codec.encode(dto), throwsFormatException);
      expect(() => mapper.toDomain(dto), throwsFormatException);
    }
  });

  test(
    'Golden Sample round trip retains Step 8 and all three Step 9 results',
    () {
      final restored = mapper.toDomain(codec.decode(codec.encode(sampleDto())));
      expectSample(restored);
      final plan = restored.planConditions;
      final result = calculateRepairReserve(
        referenceMonth: goldenSample.referenceMonth,
        currentCarFundYen: plan.currentCarFundYen,
        reserveTargetMonth: reserveMonth(
          restored.ownerBirthMonth,
          plan.reserveTargetAge,
        ),
        largeRepairReserveYen: plan.largeRepairReserveYen,
        plannedExpenses: restored.plannedExpenses,
      ) as RepairReserveSuccess;
      expect(result.plannedExpensesOnlyMonthlyYen, 11341);
      expect(result.repairIncludedMonthlyYen, 29808);
      expect(result.additionalMonthlyYen, 18467);

      List<Object> timeline(RestoredCarData data) =>
          calculateFutureTimeline(
                referenceMonth: goldenSample.referenceMonth,
                birthMonth: data.ownerBirthMonth,
                firstRegistrationMonth: data.car.firstRegistrationMonth,
                ownershipTargetMonth: reserveMonth(
                  data.ownerBirthMonth,
                  data.planConditions.ownershipTargetAge,
                ),
                currentMileageKm: data.planConditions.currentMileageKm,
                annualMileageKm: data.planConditions.annualMileageKm,
                plannedExpenses: data.plannedExpenses,
              )
              .map(
                (year) => [
                  year.year,
                  year.ownerAge,
                  year.carAge,
                  year.mileageKm,
                  year.isCurrent,
                  year.totalYen,
                  year.expenses.map((e) => e.id).toList(),
                ],
              )
              .toList();
      final before = timeline((
        ownerBirthMonth: goldenSample.owner.birthMonth,
        car: goldenSample.car,
        planConditions: conditions(),
        plannedExpenses: goldenSample.plannedExpenses,
      ));
      expect(timeline(restored), before);
      expect(before, hasLength(15));
    },
  );

  test('array order is preserved but does not change Step 9 totals', () {
    final restored = mapper.toDomain(
      codec.decode(
        codec.encode(
          sampleDto(expenses: goldenSample.plannedExpenses.reversed.toList()),
        ),
      ),
    );
    expect(restored.plannedExpenses.map((e) => e.id), [6, 5, 4, 3, 2, 1]);
    final result = calculateRepairReserve(
      referenceMonth: goldenSample.referenceMonth,
      currentCarFundYen: restored.planConditions.currentCarFundYen,
      reserveTargetMonth: reserveMonth(
        goldenSample.owner.birthMonth,
        restored.planConditions.reserveTargetAge,
      ),
      largeRepairReserveYen: restored.planConditions.largeRepairReserveYen,
      plannedExpenses: restored.plannedExpenses,
    ) as RepairReserveSuccess;
    expect(result.plannedExpensesOnlyMonthlyYen, 11341);
    expect(result.repairIncludedMonthlyYen, 29808);
    expect(result.additionalMonthlyYen, 18467);
  });
}
