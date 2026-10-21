import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:keep_my_car/backup/src/zip_backup_structure.dart';
import 'package:keep_my_car/backup/src/zip_plan_schema_v1.dart';
import 'package:keep_my_car/backup/zip_backup_codec.dart';
import 'package:keep_my_car/backup/zip_backup_result.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/sample_data/golden_sample.dart';

import '../plan_test_support.dart' show conditions, session;
import 'zip_test_support.dart';

const codec = ZipBackupCodec();
const schema = ZipPlanSchemaV1();
final failure = isA<ZipBackupFailure>();

Future<void> rejected(Uint8List bytes, [ZipBackupIssue? issue]) async {
  final result = await codec.decode(bytes);
  expect(
    result,
    issue == null ? failure : failure.having((r) => r.issue, 'issue', issue),
  );
}

Map<String, dynamic> object(Map<String, dynamic> root, String key) =>
    root[key] as Map<String, dynamic>;
Map<String, dynamic> expense(Map<String, dynamic> root) =>
    (root['plannedExpenses'] as List).first as Map<String, dynamic>;
Uint8List jpeg({int width = 8, int height = 6}) =>
    img.encodeJpg(img.Image(width: width, height: height));

// Observe public stream/sink boundaries, not zlib's internal consumption or
// allocation. The codec's use of this same streaming path is a static check.
class _ObservedBoundedOutput extends BackupBoundedOutput {
  _ObservedBoundedOutput(super.maximum, this.input);
  final InputStream input;
  final writes = <({int inputPosition, int byteCount})>[];

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    writes.add((
      inputPosition: input.position,
      byteCount: length ?? bytes.length,
    ));
    super.writeBytes(bytes, length: length);
  }
}

void main() {
  group('normal external contracts', () {
    for (final method in ['stored', 'deflate']) {
      test('.NET external $method fixture preserves all fields', () async {
        final bytes = File('test/backup/fixtures/zip_v1_$method.zip')
            .readAsBytesSync();
        expect(inspectBackupZip(bytes).map((e) => e.method).toSet(), {
          method == 'stored' ? 0 : 8,
        });
        final result = await codec.decode(bytes) as ZipBackupSuccess;
        expect(result.jpeg, isNull);
        expect(result.plan.photoId, isNull);
        expect(
          jsonDecode(utf8.decode(schema.encode(result.plan))),
          zipPlanFixture(),
        );
        expect(result.plan.plannedExpenses.map((e) => e.id), [17, -3, 0]);
        expect(result.plan.planConditions.fundingPlanEnabled, false);
        expect(result.plan.planConditions.currentCarFundYen, 500000);
        expect(result.plan.planConditions.largeRepairReserveYen, 2000000);
        expect(result.plan.plannedExpenses[1].memo, isNull);
      });
    }
    for (final method in [0, 8]) {
      for (final hasPhoto in [false, true]) {
        for (final descriptor in [false, true]) {
          test(
            'method $method photo $hasPhoto descriptor $descriptor',
            () async {
              final photo = hasPhoto ? jpeg() : null;
              final result = await codec.decode(
                fixtureZip(
                  photo: photo,
                  method: method,
                  flags: descriptor ? 8 : 0,
                ),
              ) as ZipBackupSuccess;
              expect(result.jpeg, photo);
            },
          );
        }
      }
    }
    test(
      'encode uses fixed Stored profile and drops internal photoId',
      () async {
        final source = schema.decode(jsonBytes(zipPlanFixture()));
        final plan = (
          photoId: '12345678-1234-4123-8123-123456789abc',
          ownerBirthMonth: source.ownerBirthMonth,
          car: source.car,
          planConditions: source.planConditions,
          plannedExpenses: source.plannedExpenses,
        );
        for (final photo in [null, jpeg()]) {
          final bytes = await codec.encode(plan, jpeg: photo);
          expect(bytes.length, lessThanOrEqualTo(ZipBackupLimits.zip));
          final entries = inspectBackupZip(bytes);
          expect(entries.length, photo == null ? 2 : 3);
          expect(entries.every((e) => e.method == 0), true);
          for (final e in entries) {
            expect(read16(bytes, e.localOffset + 6) & 8, 0);
            expect(read16(bytes, e.localOffset + 28), 0);
          }
          expect(read16(bytes, bytes.length - 2), 0);
          final restored = await codec.decode(bytes) as ZipBackupSuccess;
          expect(restored.plan.photoId, isNull);
          expect(schema.encode(restored.plan), schema.encode(source));
          expect(restored.jpeg, photo);
          final entry = entries.singleWhere((e) => e.name == 'plan.json');
          final text = utf8.decode(bytes.sublist(entry.dataOffset, entry.end));
          expect(text, isNot(contains('photoId')));
          expect(text, isNot(contains('formatVersion')));
        }
      },
    );
    test(
      'JPEG success owns immutable bytes, input later mutation is harmless',
      () async {
        final original = jpeg();
        final bytes = fixtureZip(photo: original);
        final result = await codec.decode(bytes) as ZipBackupSuccess;
        bytes.fillRange(0, bytes.length, 0);
        expect(result.jpeg, original);
        expect(() => result.jpeg![0] = 0, throwsUnsupportedError);
        expect(
          () => result.jpeg!.buffer.asUint8List()[0] = 0,
          throwsUnsupportedError,
        );
        final direct = ZipBackupSuccess(result.plan, original);
        original[0] = 0;
        expect(direct.jpeg![0], 0xff);
        expect(
          () => result.plan.plannedExpenses.clear(),
          throwsUnsupportedError,
        );
      },
    );
    test(
      'comments, reversed central order and Deflate option flags accepted',
      () async {
        final plan = jsonBytes(zipPlanFixture());
        final bytes = testZip([
          TestZipEntry(
            'plan.json',
            plan,
            method: 8,
            flags: 0x806,
            comment: 'entry comment 🚗',
          ),
          TestZipEntry(
            'manifest.json',
            jsonBytes(zipManifest(plan)),
            method: 8,
          ),
        ], comment: 'ZIP comment PK\u0005\u0006');
        final cd = centralOffset(
          Uint8List.sublistView(
            bytes,
            0,
            bytes.length - utf8.encode('ZIP comment PK\u0005\u0006').length,
          ),
        );
        final firstSize = 46 + read16(bytes, cd + 28) + read16(bytes, cd + 32);
        final eocd =
            cd +
            read32(
              bytes,
              bytes.length -
                  utf8.encode('ZIP comment PK\u0005\u0006').length -
                  10,
            );
        final reversed = Uint8List.fromList([
          ...bytes.sublist(0, cd),
          ...bytes.sublist(cd + firstSize, eocd),
          ...bytes.sublist(cd, cd + firstSize),
          ...bytes.sublist(eocd),
        ]);
        expect(await codec.decode(reversed), isA<ZipBackupSuccess>());
      },
    );
    test('Golden Sample survives ZIP and retains planning results', () async {
      final original = (
        photoId: null,
        ownerBirthMonth: goldenSample.owner.birthMonth,
        car: goldenSample.car,
        planConditions: conditions(),
        plannedExpenses: goldenSample.plannedExpenses,
      );
      final decoded =
          await codec.decode(await codec.encode(original)) as ZipBackupSuccess;
      expect(schema.encode(decoded.plan), schema.encode(original));
      final result =
          session(
                initial: decoded.plan.planConditions,
                expenses: decoded.plan.plannedExpenses,
              ).reserveResult
              as RepairReserveSuccess;
      expect(result.plannedExpensesOnlyMonthlyYen, 11341);
      expect(result.repairIncludedMonthlyYen, 29808);
      expect(result.additionalMonthlyYen, 18467);
    });
    test('EOCD-shaped bytes inside a valid ZIP comment are ignored', () async {
      // Fake EOCD has the right signature/length but cannot describe a backup.
      final fake = ByteData(22)..setUint32(0, 0x06054b50, Endian.little);
      final plan = jsonBytes(zipPlanFixture());
      final bytes = testZip([
        TestZipEntry('manifest.json', jsonBytes(zipManifest(plan))),
        TestZipEntry('plan.json', plan),
      ], comment: String.fromCharCodes(fake.buffer.asUint8List()));
      expect(await codec.decode(bytes), isA<ZipBackupSuccess>());
    });
  });

  group('ZIP structure before expansion', () {
    void matching16(
      Uint8List bytes,
      int central,
      int localField,
      int centralField,
      int value,
    ) {
      put16(bytes, localField, value);
      put16(bytes, central + centralField, value);
    }

    final cases = <String, void Function(Uint8List, int, int)>{
      'EOCD signature': (b, c, e) => put32(b, e, 0),
      'central signature': (b, c, e) => put32(b, c, 0),
      'local signature': (b, c, e) => put32(b, 0, 0),
      'entry counts mismatch': (b, c, e) => put16(b, e + 8, 3),
      'too few entries': (b, c, e) {
        put16(b, e + 8, 1);
        put16(b, e + 10, 1);
      },
      'too many entries': (b, c, e) {
        put16(b, e + 8, 4);
        put16(b, e + 10, 4);
      },
      'CD size': (b, c, e) => put32(b, e + 12, 1),
      'CD offset extreme': (b, c, e) => put32(b, e + 16, 0xfffffffe),
      'local offset extreme': (b, c, e) => put32(b, c + 42, 0xfffffffe),
      'local overlaps CD': (b, c, e) => put32(b, c + 42, c),
      'local-central flags': (b, c, e) => put16(b, 6, 0x800),
      'local-central method': (b, c, e) => put16(b, 8, 8),
      'local-central version': (b, c, e) => put16(b, 4, 10),
      'local-central date': (b, c, e) => put16(b, 12, 1),
      'local-central CRC': (b, c, e) => put32(b, 14, 1),
      'local-central compressed size': (b, c, e) => put32(b, 18, 1),
      'local-central size': (b, c, e) => put32(b, 22, 1),
      'local-central name length': (b, c, e) => put16(b, 26, 1),
      'local-central name': (b, c, e) => b[30] = 120,
      'name boundary': (b, c, e) => put16(b, c + 28, 65535),
      'entry comment boundary': (b, c, e) => put16(b, c + 32, 65535),
      'ZIP comment boundary': (b, c, e) => put16(b, e + 20, 1),
      'central extra': (b, c, e) => put16(b, c + 30, 4),
      'local extra': (b, c, e) => put16(b, 28, 4),
      'symlink unix': (b, c, e) => put32(b, c + 38, 0xa1ff0000),
      'directory unix': (b, c, e) => put32(b, c + 38, 0x41ff0000),
      'FIFO unix': (b, c, e) => put32(b, c + 38, 0x11ff0000),
      'directory DOS': (b, c, e) => put32(b, c + 38, 0x10),
      'volume DOS': (b, c, e) => put32(b, c + 38, 8),
      'device DOS': (b, c, e) => put32(b, c + 38, 0x40),
      'split disk': (b, c, e) => put16(b, e + 4, 1),
      'split central disk': (b, c, e) => put16(b, e + 6, 1),
      'split entry disk': (b, c, e) => put16(b, c + 34, 1),
      'ZIP64 count': (b, c, e) => put16(b, e + 10, 65535),
      'ZIP64 CD size': (b, c, e) => put32(b, e + 12, 0xffffffff),
      'ZIP64 CD offset': (b, c, e) => put32(b, e + 16, 0xffffffff),
      'ZIP64 entry size': (b, c, e) {
        put32(b, 22, 0xffffffff);
        put32(b, c + 24, 0xffffffff);
      },
      'ZIP64 compressed size': (b, c, e) {
        put32(b, 18, 0xffffffff);
        put32(b, c + 20, 0xffffffff);
      },
      'ZIP64 local offset': (b, c, e) => put32(b, c + 42, 0xffffffff),
      // Keep matching headers so the dedicated version/method/flag guards,
      // rather than a local-central mismatch, must reject these profiles.
      'ZIP64 version': (b, c, e) => matching16(b, c, 4, 6, 45),
      'unsupported version': (b, c, e) => matching16(b, c, 4, 6, 21),
      'encryption': (b, c, e) => matching16(b, c, 6, 8, 1),
      'strong encryption': (b, c, e) => matching16(b, c, 6, 8, 64),
      'reserved flag': (b, c, e) => matching16(b, c, 6, 8, 0x8000),
      'stored deflate flag': (b, c, e) => matching16(b, c, 6, 8, 2),
      'unsupported compression': (b, c, e) => matching16(b, c, 8, 10, 12),
      'stored unequal sizes': (b, c, e) {
        put32(b, c + 24, 1);
        put32(b, 22, 1);
      },
    };
    const unsupportedCases = {
      'central extra',
      'local extra',
      'symlink unix',
      'directory unix',
      'FIFO unix',
      'directory DOS',
      'volume DOS',
      'device DOS',
      'split disk',
      'split central disk',
      'split entry disk',
      'ZIP64 count',
      'ZIP64 CD size',
      'ZIP64 CD offset',
      'ZIP64 entry size',
      'ZIP64 compressed size',
      'ZIP64 local offset',
      'ZIP64 version',
      'unsupported version',
      'encryption',
      'strong encryption',
      'reserved flag',
      'stored deflate flag',
      'unsupported compression',
    };
    for (final item in cases.entries) {
      test(item.key, () async {
        final bytes = fixtureZip();
        item.value(bytes, centralOffset(bytes), bytes.length - 22);
        await rejected(
          bytes,
          unsupportedCases.contains(item.key)
              ? ZipBackupIssue.unsupportedZip
              : ZipBackupIssue.invalidZip,
        );
      });
    }
    for (final name in [
      '../plan.json',
      '/plan.json',
      'a/plan.json',
      'a\\plan.json',
      'plan.json/',
      'PLAN.JSON',
      'plan.json\u0000',
      'other.txt',
    ]) {
      test('exact filename rejects $name', () async {
        await rejected(
          testZip([
            TestZipEntry('manifest.json', Uint8List(0)),
            TestZipEntry(name, Uint8List(0)),
          ]),
          ZipBackupIssue.invalidZip,
        );
      });
    }
    test(
      'duplicate names are rejected before archive can aggregate them',
      () async {
        await rejected(
          testZip([
            TestZipEntry('manifest.json', Uint8List(0)),
            TestZipEntry('manifest.json', Uint8List(0)),
          ]),
          ZipBackupIssue.invalidZip,
        );
      },
    );
    test('unexpected third and fourth entries', () async {
      final plan = jsonBytes(zipPlanFixture());
      for (final count in [1, 2]) {
        await rejected(
          testZip([
            TestZipEntry('manifest.json', jsonBytes(zipManifest(plan))),
            TestZipEntry('plan.json', plan),
            for (var i = 0; i < count; i++)
              TestZipEntry('extra$i', Uint8List(0)),
          ]),
          ZipBackupIssue.invalidZip,
        );
      }
    });
    test('leading/trailing bytes, gaps and overlapping entries', () async {
      final bytes = fixtureZip();
      await rejected(Uint8List.fromList([0, ...bytes]));
      await rejected(Uint8List.fromList([...bytes, 0]));
      final cd = centralOffset(bytes);
      final second = cd + 46 + read16(bytes, cd + 28);
      put32(bytes, second + 42, 0);
      await rejected(bytes, ZipBackupIssue.invalidZip);
      final gap = fixtureZip();
      final manifestSize = read32(gap, 18);
      put32(gap, 18, manifestSize - 1);
      put32(gap, 22, manifestSize - 1);
      final c = centralOffset(gap);
      put32(gap, c + 20, manifestSize - 1);
      put32(gap, c + 24, manifestSize - 1);
      await rejected(gap, ZipBackupIssue.invalidZip);
    });
    for (final offset in [0, 4, 8, 12]) {
      test('descriptor field corruption $offset', () async {
        final bytes = fixtureZip(flags: 8);
        final entry = inspectBackupZip(bytes).first;
        put32(bytes, entry.end - 16 + offset, 0x11223344);
        await rejected(bytes, ZipBackupIssue.invalidZip);
      });
    }
    test(
      'descriptor local values may be zero or match, never arbitrary',
      () async {
        final bytes = fixtureZip(flags: 8);
        final cd = centralOffset(bytes);
        put32(bytes, 14, read32(bytes, cd + 16));
        put32(bytes, 18, read32(bytes, cd + 20));
        put32(bytes, 22, read32(bytes, cd + 24));
        expect(await codec.decode(bytes), isA<ZipBackupSuccess>());
        put32(bytes, 22, 1);
        await rejected(bytes, ZipBackupIssue.invalidZip);
      },
    );
    test('truncated structures and random inputs fail safely', () async {
      final bytes = fixtureZip();
      for (final length in [
        0,
        1,
        21,
        22,
        29,
        42,
        bytes.length - 1,
        bytes.length - 22,
      ]) {
        await rejected(Uint8List.sublistView(bytes, 0, length));
      }
      final random = Random(15);
      for (var i = 0; i < 100; i++) {
        await rejected(
          Uint8List.fromList(List.generate(i * 7, (_) => random.nextInt(256))),
        );
      }
    });
  });

  group('size limits and bounded expansion', () {
    for (final delta in [-1, 0, 1]) {
      test('ZIP 12MiB boundary $delta', () async {
        // Smaller/equal still fail structure; only +1 is classified as size.
        await rejected(
          Uint8List(ZipBackupLimits.zip + delta),
          delta > 0 ? ZipBackupIssue.sizeLimit : ZipBackupIssue.invalidZip,
        );
      });
    }
    for (final item in ZipBackupLimits.files.entries) {
      for (final delta in [-1, 0, 1]) {
        test('${item.key} declared/actual boundary $delta', () async {
          final bytes = Uint8List(item.value + delta);
          final entries = [
            TestZipEntry(
              'manifest.json',
              item.key == 'manifest.json' ? bytes : Uint8List(0),
              method: 8,
            ),
            TestZipEntry(
              'plan.json',
              item.key == 'plan.json' ? bytes : Uint8List(0),
              method: 8,
            ),
            if (item.key == 'photo.jpg')
              TestZipEntry('photo.jpg', bytes, method: 8),
          ];
          final zip = testZip(entries);
          if (delta <= 0) {
            expect(inspectBackupZip(zip), hasLength(entries.length));
            // Expansion reaches JSON validation without a limit failure.
            await rejected(zip, ZipBackupIssue.invalidManifest);
          } else {
            await rejected(zip, ZipBackupIssue.sizeLimit);
          }
        });
      }
    }
    test(
      'valid plan at 5MiB accepted, +1 rejected, including encode',
      () async {
        final root = zipPlanFixture();
        final e = expense(root);
        e['memo'] = '';
        final baseSize = jsonBytes(root).length;
        for (final delta in [-1, 0, 1]) {
          e['memo'] =
              'a' * (ZipBackupLimits.files['plan.json']! - baseSize + delta);
          final plan = jsonBytes(root);
          final zip = fixtureZip(plan: plan, method: 8);
          if (delta <= 0) {
            expect(await codec.decode(zip), isA<ZipBackupSuccess>());
            final domain = schema.decode(plan);
            expect(
              await codec.decode(await codec.encode(domain)),
              isA<ZipBackupSuccess>(),
            );
          } else {
            await rejected(zip, ZipBackupIssue.sizeLimit);
            await expectLater(
              codec.encode(schema.decode(plan)),
              throwsA(
                failure.having(
                  (r) => r.issue,
                  'issue',
                  ZipBackupIssue.sizeLimit,
                ),
              ),
            );
          }
        }
      },
    );
    test('valid padded manifest 32KiB boundaries accepted', () async {
      final plan = jsonBytes(zipPlanFixture());
      final base = jsonBytes(zipManifest(plan));
      for (final delta in [-1, 0, 1]) {
        final manifest = Uint8List.fromList([
          ...base,
          ...List.filled(32768 + delta - base.length, 32),
        ]);
        final zip = fixtureZip(plan: plan, manifestBytes: manifest, method: 8);
        if (delta <= 0) {
          expect(await codec.decode(zip), isA<ZipBackupSuccess>());
        } else {
          await rejected(zip, ZipBackupIssue.sizeLimit);
        }
      }
    });
    test('valid JPEG fill bytes at 3MiB boundary, +1 rejected', () async {
      final base = jpeg();
      final plan = schema.decode(jsonBytes(zipPlanFixture()));
      for (final delta in [-1, 0, 1]) {
        final padded = Uint8List.fromList([
          ...base.sublist(0, base.length - 2),
          ...List.filled(3 * 1024 * 1024 + delta - base.length, 0xff),
          0xff,
          0xd9,
        ]);
        final bytes = fixtureZip(photo: padded, method: 8);
        if (delta <= 0) {
          final result = await codec.decode(bytes) as ZipBackupSuccess;
          expect(result.jpeg, padded);
          expect(
            await codec.decode(await codec.encode(plan, jpeg: padded)),
            isA<ZipBackupSuccess>(),
          );
        } else {
          await rejected(bytes, ZipBackupIssue.sizeLimit);
        }
      }
    });
    test(
      'forged small declarations cannot inflate beyond any file cap',
      () async {
        for (final item in ZipBackupLimits.files.entries) {
          final bomb = Uint8List(item.value + 1);
          final zip = testZip([
            TestZipEntry(
              'manifest.json',
              item.key == 'manifest.json' ? bomb : Uint8List(0),
              method: 8,
              declaredSize: 0,
            ),
            TestZipEntry(
              'plan.json',
              item.key == 'plan.json' ? bomb : Uint8List(0),
              method: 8,
              declaredSize: 0,
            ),
            if (item.key == 'photo.jpg')
              TestZipEntry('photo.jpg', bomb, method: 8, declaredSize: 0),
          ]);
          expect(zip.length, lessThan(16000));
          await rejected(zip, ZipBackupIssue.sizeLimit);
        }
      },
    );
    test('native expansion streams output and stops before all input is read', () {
      // An incompressible prefix keeps compressed bytes unread when the bound
      // is reached; a zero suffix adds expansion pressure. Only 640KiB raw.
      final raw = Uint8List(640 * 1024);
      final random = Random(15);
      for (var i = 0; i < 128 * 1024; i++) {
        raw[i] = random.nextInt(256);
      }
      final compressed = Uint8List.fromList(ZLibCodec(raw: true).encode(raw));
      final input = InputMemoryStream(compressed);
      final output = _ObservedBoundedOutput(96 * 1024, input);
      expect(
        () => const ZLibDecoder().decodeStream(input, output, raw: true),
        throwsA(
          failure.having((r) => r.issue, 'issue', ZipBackupIssue.sizeLimit),
        ),
      );
      expect(output.length, inInclusiveRange(1, output.maximum));
      expect(input.position, lessThan(input.totalLength));
      expect(output.writes.length, greaterThan(1));
      expect(output.writes.first.inputPosition, lessThan(input.totalLength));
      expect(output.writes.every((w) => w.byteCount < raw.length), true);

      // Safe, finite negative control: a full decode followed by one sink write
      // still throws at the bound, but fails the streaming observations above.
      final batchInput = InputMemoryStream(compressed);
      final batchOutput = _ObservedBoundedOutput(output.maximum, batchInput);
      final all = const ZLibDecoder().decodeBytes(
        batchInput.readBytes(batchInput.length).toUint8List(),
        raw: true,
      );
      expect(all, raw);
      expect(() => batchOutput.writeBytes(all), throwsA(failure));
      expect(batchOutput.writes, hasLength(1));
      expect(batchOutput.writes.single.inputPosition, batchInput.totalLength);
      expect(batchOutput.writes.single.byteCount, raw.length);
      expect(batchOutput.length, 0);
    });
    test('all output methods check before changing buffer', () {
      for (final write in <void Function(BackupBoundedOutput)>[
        (o) => o.writeByte(1),
        (o) => o.writeBytes([1]),
        (o) => o.writeStream(InputMemoryStream([1])),
        (o) => o.writeBackReference(1, 1),
      ]) {
        final output = BackupBoundedOutput(3)..writeBytes([1, 2, 3]);
        expect(() => write(output), throwsA(failure));
        expect(output.getBytes(), [1, 2, 3]);
      }
    });
    test('shared total bound and stored writes are bounded', () {
      final out = BackupBoundedOutput(ZipBackupLimits.expanded);
      out.writeBytes(Uint8List(ZipBackupLimits.expanded));
      expect(() => out.writeByte(0), throwsA(failure));
      expect(out.length, ZipBackupLimits.expanded);
      expect(
        ZipBackupLimits.files.values.reduce((a, b) => a + b),
        lessThan(ZipBackupLimits.expanded),
      );
    });
    test('extreme declarations refused before allocation', () async {
      final zip = fixtureZip();
      final cd = centralOffset(zip);
      put32(zip, cd + 24, 0xfffffffe);
      put32(zip, 22, 0xfffffffe);
      await rejected(zip, ZipBackupIssue.sizeLimit);
    });
  });

  group('Deflate and checksums (B案)', () {
    final plan = jsonBytes(zipPlanFixture());
    Uint8List compressedPlan(
      Uint8List compressed, {
      int? declaredSize,
      int? crc,
    }) => testZip([
      TestZipEntry('manifest.json', jsonBytes(zipManifest(plan))),
      TestZipEntry(
        'plan.json',
        plan,
        method: 8,
        compressed: compressed,
        declaredSize: declaredSize,
        crc: crc,
      ),
    ]);
    for (final blockSize in [65535, 17]) {
      test('explicit raw block size $blockSize', () async {
        expect(
          await codec.decode(
            compressedPlan(rawBlocks(plan, blockSize: blockSize)),
          ),
          isA<ZipBackupSuccess>(),
        );
      });
    }
    test(
      'corrupt block, truncation losing output, size and CRC mismatch',
      () async {
        final raw = rawBlocks(plan);
        await rejected(
          compressedPlan(Uint8List.fromList([7, 0, 0])),
          ZipBackupIssue.integrity,
        );
        await rejected(
          compressedPlan(Uint8List.sublistView(raw, 0, raw.length - 10)),
          ZipBackupIssue.integrity,
        );
        await rejected(
          compressedPlan(raw, declaredSize: plan.length + 1),
          ZipBackupIssue.integrity,
        );
        await rejected(compressedPlan(raw, crc: 0), ZipBackupIssue.integrity);
      },
    );
    test('B案: missing final bit retains same output, CRC and SHA', () async {
      // Native Dart accepts this incomplete stream. All uncompressed bytes
      // remain identical; capacity, CRC, SHA and schema checks still apply.
      expect(
        await codec.decode(compressedPlan(rawBlocks(plan, finalBit: false))),
        isA<ZipBackupSuccess>(),
      );
    });
    test(
      'B案: trailing compressed bytes retain same output, CRC and SHA',
      () async {
        expect(
          await codec.decode(
            compressedPlan(
              Uint8List.fromList([...rawBlocks(plan), 17, 34, 51]),
            ),
          ),
          isA<ZipBackupSuccess>(),
        );
      },
    );
    test('CRC is explicit for Stored and each entry', () async {
      for (final photo in [null, jpeg()]) {
        final original = fixtureZip(photo: photo);
        for (final entry in inspectBackupZip(original)) {
          final bytes = Uint8List.fromList(original);
          bytes[entry.dataOffset] ^= 1;
          await rejected(bytes, ZipBackupIssue.integrity);
        }
      }
    });
    test('CRC recomputed still cannot bypass SHA on plan or photo', () async {
      final photo = jpeg();
      final originalPlan = jsonBytes(zipPlanFixture());
      final manifest = zipManifest(originalPlan, photo);
      final changed = Uint8List.fromList(originalPlan)..[0] = 32;
      await rejected(
        fixtureZip(plan: changed, photo: photo, manifest: manifest),
        ZipBackupIssue.integrity,
      );
      final changedPhoto = Uint8List.fromList(photo)..[0] = 0;
      await rejected(
        fixtureZip(plan: originalPlan, photo: changedPhoto, manifest: manifest),
        ZipBackupIssue.integrity,
      );
    });
  });

  group('manifest strict validation', () {
    final plan = jsonBytes(zipPlanFixture());
    for (final key in [
      'format',
      'formatVersion',
      'planSchemaVersion',
      'hasPhoto',
      'files',
    ]) {
      test('missing $key', () async {
        await rejected(
          fixtureZip(plan: plan, manifest: zipManifest(plan)..remove(key)),
          ZipBackupIssue.invalidManifest,
        );
      });
      test('null $key', () async {
        await rejected(
          fixtureZip(plan: plan, manifest: zipManifest(plan)..[key] = null),
          ZipBackupIssue.invalidManifest,
        );
      });
    }
    for (final versionKey in ['formatVersion', 'planSchemaVersion']) {
      for (final value in [0, -1, 1.0, '1', true, 2]) {
        test('$versionKey $value (${value.runtimeType})', () async {
          await rejected(
            fixtureZip(
              plan: plan,
              manifest: zipManifest(plan)..[versionKey] = value,
            ),
            value == 2
                ? ZipBackupIssue.unsupportedVersion
                : ZipBackupIssue.invalidManifest,
          );
        });
      }
    }
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'wrong format': (m) => m['format'] = 'keep-my-car-backup',
      'photo presence': (m) => m['hasPhoto'] = true,
      'photo integer': (m) => m['hasPhoto'] = 0,
      'unknown root': (m) => m['extra'] = 0,
      'files array': (m) => m['files'] = [],
      'files missing plan': (m) => object(m, 'files').clear(),
      'files includes manifest': (m) =>
          object(m, 'files')['manifest.json'] = {},
      'files extra photo': (m) => object(m, 'files')['photo.jpg'] = {},
      'entry unknown': (m) =>
          object(object(m, 'files'), 'plan.json')['extra'] = 1,
      'entry missing size': (m) =>
          object(object(m, 'files'), 'plan.json').remove('sizeBytes'),
      'entry missing hash': (m) =>
          object(object(m, 'files'), 'plan.json').remove('sha256'),
      'entry null': (m) => object(m, 'files')['plan.json'] = null,
    };
    for (final item in mutations.entries) {
      test(item.key, () async {
        final manifest = zipManifest(plan);
        item.value(manifest);
        await rejected(
          fixtureZip(plan: plan, manifest: manifest),
          ZipBackupIssue.invalidManifest,
        );
      });
    }
    for (final hash in [
      null,
      1,
      'A' * 64,
      '0' * 63,
      '0' * 65,
      'g' * 64,
      '0' * 63 + '\n',
    ]) {
      test('invalid SHA syntax $hash', () async {
        final manifest = zipManifest(plan);
        object(object(manifest, 'files'), 'plan.json')['sha256'] = hash;
        await rejected(
          fixtureZip(plan: plan, manifest: manifest),
          ZipBackupIssue.invalidManifest,
        );
      });
    }
    for (final size in [-1, 1.0, '1', true, plan.length + 1]) {
      test('manifest size $size (${size.runtimeType})', () async {
        final manifest = zipManifest(plan);
        object(object(manifest, 'files'), 'plan.json')['sizeBytes'] = size;
        await rejected(
          fixtureZip(plan: plan, manifest: manifest),
          size == plan.length + 1
              ? ZipBackupIssue.integrity
              : ZipBackupIssue.invalidManifest,
        );
      });
    }
    test('valid but incorrect hash rejected', () async {
      final manifest = zipManifest(plan);
      object(object(manifest, 'files'), 'plan.json')['sha256'] = '0' * 64;
      await rejected(
        fixtureZip(plan: plan, manifest: manifest),
        ZipBackupIssue.integrity,
      );
    });
    test('ZIP photo requires hasPhoto and declaration', () async {
      await rejected(
        fixtureZip(plan: plan, photo: jpeg(), manifest: zipManifest(plan)),
        ZipBackupIssue.invalidManifest,
      );
    });
  });

  group('strict UTF8/JSON for both documents', () {
    for (final target in ['manifest', 'plan']) {
      final source = jsonEncode(
        target == 'manifest'
            ? zipManifest(jsonBytes(zipPlanFixture()))
            : zipPlanFixture(),
      );
      final invalid = <String, Uint8List>{
        'BOM': Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(source)]),
        'malformed UTF8': Uint8List.fromList([0xc0, 0xaf]),
        'non object': utf8.encode('[]'),
        'truncated': utf8.encode(source.substring(0, source.length - 1)),
        'trailing JSON': utf8.encode('$source {}'),
        'trailing comma': utf8.encode(
          '${source.substring(0, source.length - 1)},}',
        ),
        'deep nesting': utf8.encode('${'[' * 10000}0${']' * 10000}'),
        'duplicate root': utf8.encode(
          source.replaceFirst(
            '{',
            '{"${target == 'manifest' ? 'format' : 'ownerBirthMonth'}":null,',
          ),
        ),
        'duplicate escaped root': utf8.encode(
          source.replaceFirst(
            '{',
            target == 'manifest'
                ? r'{"\u0066ormat":null,'
                : r'{"\u006fwnerBirthMonth":null,',
          ),
        ),
        'unknown key': utf8.encode(source.replaceFirst('{', '{"unknown":0,')),
      };
      for (final item in invalid.entries) {
        test('$target ${item.key}', () async {
          final bytes = target == 'manifest'
              ? fixtureZip(manifestBytes: item.value)
              : fixtureZip(plan: item.value);
          await rejected(
            bytes,
            target == 'manifest'
                ? ZipBackupIssue.invalidManifest
                : ZipBackupIssue.invalidPlan,
          );
        });
      }
    }
    test('nested duplicate keys at every object level', () async {
      final plan = jsonEncode(zipPlanFixture());
      for (final fragment in ['"name":', '"fundingPlanEnabled":', '"memo":']) {
        await rejected(
          fixtureZip(
            plan: utf8.encode(
              plan.replaceFirst(fragment, '$fragment null,$fragment'),
            ),
          ),
          ZipBackupIssue.invalidPlan,
        );
      }
      final manifest = jsonEncode(zipManifest(jsonBytes(zipPlanFixture())));
      for (final fragment in ['"plan.json":', '"sizeBytes":', '"sha256":']) {
        await rejected(
          fixtureZip(
            manifestBytes: utf8.encode(
              manifest.replaceFirst(fragment, '$fragment null,$fragment'),
            ),
          ),
          ZipBackupIssue.invalidManifest,
        );
      }
    });
    test(
      'Unicode, escape, whitespace and key order accepted; raw bytes hashed',
      () async {
        final root = zipPlanFixture();
        expense(root)['memo'] = 'Unicode 日本語 🚗 "quote" \\ {"name":[]}\n\t';
        final reordered = Map.fromEntries(root.entries.toList().reversed);
        final escaped = const JsonEncoder.withIndent('  ')
            .convert(reordered)
            .replaceFirst('ownerBirthMonth', r'\u006fwnerBirthMonth');
        final bytes = utf8.encode(' \r\n$escaped\t');
        final decoded =
            await codec.decode(fixtureZip(plan: bytes)) as ZipBackupSuccess;
        expect(jsonDecode(utf8.decode(schema.encode(decoded.plan))), root);
      },
    );
  });

  group('Plan/Domain contract', () {
    for (final section in ['root', 'car', 'planConditions', 'expense']) {
      Map<String, dynamic> target(Map<String, dynamic> root) =>
          switch (section) {
            'root' => root,
            'expense' => expense(root),
            _ => object(root, section),
          };
      for (final key in target(zipPlanFixture()).keys) {
        test('$section.$key required', () async {
          final root = zipPlanFixture();
          target(root).remove(key);
          await rejected(
            fixtureZip(plan: jsonBytes(root)),
            ZipBackupIssue.invalidPlan,
          );
        });
        if (key != 'memo') {
          test('$section.$key nonnullable', () async {
            final root = zipPlanFixture();
            target(root)[key] = null;
            await rejected(
              fixtureZip(plan: jsonBytes(root)),
              ZipBackupIssue.invalidPlan,
            );
          });
        }
        test('$section.$key wrong type', () async {
          final root = zipPlanFixture();
          final old = target(root)[key];
          target(root)[key] = old is int
              ? 1.0
              : old is String
              ? 1
              : old is bool
              ? 'false'
              : false;
          await rejected(
            fixtureZip(plan: jsonBytes(root)),
            ZipBackupIssue.invalidPlan,
          );
        });
      }
      test('$section unknown fields', () async {
        final root = zipPlanFixture();
        target(root)['photoId'] = null;
        await rejected(
          fixtureZip(plan: jsonBytes(root)),
          ZipBackupIssue.invalidPlan,
        );
      });
    }
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'duplicate ID': (r) => (r['plannedExpenses'] as List)[1]['id'] = 17,
      'invalid basis': (r) => expense(r)['basis'] = 'other',
      'invalid status': (r) => expense(r)['status'] = 'other',
      'negative amount': (r) => expense(r)['amountYen'] = -1,
      'large amount': (r) => expense(r)['amountYen'] = 1000000001,
      'empty name': (r) => object(r, 'car')['name'] = ' ',
      'control name': (r) => object(r, 'car')['name'] = '\t愛車',
      'too long name': (r) => expense(r)['name'] = 'あ' * 41,
      'non ASCII month': (r) => r['ownerBirthMonth'] = '２０２６-01',
      'month overflow': (r) => expense(r)['plannedMonth'] = '2026-13',
      'negative mileage': (r) => object(r, 'car')['currentMileageKm'] = -1,
      'large mileage': (r) =>
          object(r, 'planConditions')['currentMileageKm'] = 2000001,
      'large annual mileage': (r) =>
          object(r, 'car')['annualMileageKm'] = 200001,
      'mileage mismatch': (r) => object(r, 'car')['currentMileageKm'] = 1,
      'annual mileage mismatch': (r) => object(r, 'car')['annualMileageKm'] = 1,
      'large age': (r) =>
          object(r, 'planConditions')['ownershipTargetAge'] = 101,
      'negative reserve age': (r) =>
          object(r, 'planConditions')['reserveTargetAge'] = -1,
      'negative fund': (r) =>
          object(r, 'planConditions')['currentCarFundYen'] = -1,
      'large reserve': (r) =>
          object(r, 'planConditions')['largeRepairReserveYen'] = 1000000001,
    };
    for (final item in mutations.entries) {
      test(item.key, () async {
        final root = zipPlanFixture();
        item.value(root);
        await rejected(
          fixtureZip(plan: jsonBytes(root)),
          ZipBackupIssue.invalidPlan,
        );
      });
    }
    test(
      'empty expenses, old months, year 0000 and age bounds preserved',
      () async {
        final root = zipPlanFixture()
          ..['ownerBirthMonth'] = '0000-01'
          ..['plannedExpenses'] = [];
        expect(
          await codec.decode(fixtureZip(plan: jsonBytes(root))),
          isA<ZipBackupSuccess>(),
        );
      },
    );
    test('encode also rejects invalid caller plans', () async {
      final plan = schema.decode(jsonBytes(zipPlanFixture()));
      final bad = (
        photoId: null,
        ownerBirthMonth: plan.ownerBirthMonth,
        car: plan.car.copyWith(currentMileageKm: 1),
        planConditions: plan.planConditions,
        plannedExpenses: plan.plannedExpenses,
      );
      await expectLater(
        codec.encode(bad),
        throwsA(
          failure.having((r) => r.issue, 'issue', ZipBackupIssue.invalidPlan),
        ),
      );
    });
  });

  group('photo and safe failure', () {
    final photos = <String, Uint8List Function()>{
      'PNG': () => img.encodePng(img.Image(width: 2, height: 2)),
      'corrupt JPEG': () => Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      'dimension': () => jpeg(width: 1601, height: 1),
      'EXIF': () => Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe1,
        0,
        4,
        0,
        0,
        ...jpeg().sublist(2),
      ]),
      'XMP': () => Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe1,
        0,
        4,
        1,
        1,
        ...jpeg().sublist(2),
      ]),
      'ICC': () => Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe2,
        0,
        4,
        0,
        0,
        ...jpeg().sublist(2),
      ]),
      'COM': () => Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xfe,
        0,
        4,
        0,
        0,
        ...jpeg().sublist(2),
      ]),
      'trailing data': () => Uint8List.fromList([...jpeg(), 0]),
    };
    for (final item in photos.entries) {
      test(
        '${item.key} rejected without processing source or creating files',
        () async {
          final photo = item.value();
          final before = Uint8List.fromList(photo);
          final plan = schema.decode(jsonBytes(zipPlanFixture()));
          await rejected(fixtureZip(photo: photo), ZipBackupIssue.invalidPhoto);
          await expectLater(
            codec.encode(plan, jpeg: photo),
            throwsA(
              failure.having(
                (r) => r.issue,
                'issue',
                ZipBackupIssue.invalidPhoto,
              ),
            ),
          );
          expect(photo, before);
        },
      );
    }
    test(
      'photo dimension 1600 accepted and 3MiB+1 rejected before validation',
      () async {
        expect(
          await codec.decode(fixtureZip(photo: jpeg(width: 1600, height: 1))),
          isA<ZipBackupSuccess>(),
        );
        final plan = schema.decode(jsonBytes(zipPlanFixture()));
        await expectLater(
          codec.encode(plan, jpeg: Uint8List(3 * 1024 * 1024 + 1)),
          throwsA(
            failure.having((r) => r.issue, 'issue', ZipBackupIssue.sizeLimit),
          ),
        );
      },
    );
    test('failures leave no partial result/state and repeated calls recover', () async {
      final original = fixtureZip(photo: jpeg());
      final before = Uint8List.fromList(original);
      for (var i = 0; i < 8; i++) {
        await rejected(Uint8List(0));
        await rejected(
          fixtureZip(photo: Uint8List(4)),
          ZipBackupIssue.invalidPhoto,
        );
        final badPlan = zipPlanFixture();
        object(badPlan, 'car')['name'] = '';
        await rejected(
          fixtureZip(plan: jsonBytes(badPlan)),
          ZipBackupIssue.invalidPlan,
        );
        expect(await codec.decode(original), isA<ZipBackupSuccess>());
      }
      expect(original, before);
      // Codec imports no repository/storage service, and its only dependencies
      // consume bytes. Existing integration regressions cover formal state.
    });
  });
}
