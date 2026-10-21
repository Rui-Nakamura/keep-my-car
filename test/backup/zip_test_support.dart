import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';

Map<String, dynamic> zipPlanFixture() =>
    jsonDecode(File('test/backup/fixtures/zip_v1_plan.json').readAsStringSync())
        as Map<String, dynamic>;

Uint8List jsonBytes(Object? value) => utf8.encode(jsonEncode(value));

Map<String, dynamic> zipManifest(Uint8List plan, [Uint8List? photo]) => {
  'format': 'keep-my-car-zip-backup',
  'formatVersion': 1,
  'planSchemaVersion': 1,
  'hasPhoto': photo != null,
  'files': <String, dynamic>{
    for (final entry in {'plan.json': plan, 'photo.jpg': ?photo}.entries)
      entry.key: <String, dynamic>{
        'sizeBytes': entry.value.length,
        'sha256': sha256.convert(entry.value).toString(),
      },
  },
};

class TestZipEntry {
  TestZipEntry(
    this.name,
    this.bytes, {
    this.method = 0,
    this.flags = 0,
    this.declaredSize,
    this.crc,
    this.compressed,
    this.attributes = 0,
    this.comment = '',
  });
  final String name;
  final Uint8List bytes;
  final int method, flags, attributes;
  final int? declaredSize, crc;
  final Uint8List? compressed;
  final String comment;
}

/// Independent fixed-profile test writer. Deflate comes from dart:io, not the
/// production archive encoder. Allows adversarial declarations and payloads.
Uint8List testZip(List<TestZipEntry> entries, {String comment = ''}) {
  final local = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  for (final entry in entries) {
    final name = utf8.encode(entry.name);
    final payload =
        entry.compressed ??
        (entry.method == 8
            ? Uint8List.fromList(ZLibCodec(raw: true).encode(entry.bytes))
            : entry.bytes);
    final size = entry.declaredSize ?? entry.bytes.length;
    final crc = entry.crc ?? getCrc32(entry.bytes);
    final descriptor = (entry.flags & 8) != 0;
    final header = ByteData(30);
    header.setUint32(0, 0x04034b50, Endian.little);
    header.setUint16(4, 20, Endian.little);
    header.setUint16(6, entry.flags, Endian.little);
    header.setUint16(8, entry.method, Endian.little);
    header.setUint32(14, descriptor ? 0 : crc, Endian.little);
    header.setUint32(18, descriptor ? 0 : payload.length, Endian.little);
    header.setUint32(22, descriptor ? 0 : size, Endian.little);
    header.setUint16(26, name.length, Endian.little);
    final directory = ByteData(46);
    directory.setUint32(0, 0x02014b50, Endian.little);
    directory.setUint16(4, 0x0314, Endian.little);
    directory.setUint16(6, 20, Endian.little);
    directory.setUint16(8, entry.flags, Endian.little);
    directory.setUint16(10, entry.method, Endian.little);
    directory.setUint32(16, crc, Endian.little);
    directory.setUint32(20, payload.length, Endian.little);
    directory.setUint32(24, size, Endian.little);
    directory.setUint16(28, name.length, Endian.little);
    final entryComment = utf8.encode(entry.comment);
    directory.setUint16(32, entryComment.length, Endian.little);
    directory.setUint32(38, entry.attributes, Endian.little);
    directory.setUint32(42, local.length, Endian.little);
    local
      ..add(header.buffer.asUint8List())
      ..add(name)
      ..add(payload);
    if (descriptor) {
      final dd = ByteData(16);
      dd.setUint32(0, 0x08074b50, Endian.little);
      dd.setUint32(4, crc, Endian.little);
      dd.setUint32(8, payload.length, Endian.little);
      dd.setUint32(12, size, Endian.little);
      local.add(dd.buffer.asUint8List());
    }
    central
      ..add(directory.buffer.asUint8List())
      ..add(name)
      ..add(entryComment);
  }
  final end = ByteData(22);
  end.setUint32(0, 0x06054b50, Endian.little);
  end.setUint16(8, entries.length, Endian.little);
  end.setUint16(10, entries.length, Endian.little);
  end.setUint32(12, central.length, Endian.little);
  end.setUint32(16, local.length, Endian.little);
  final zipComment = utf8.encode(comment);
  end.setUint16(20, zipComment.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(local.takeBytes())
        ..add(central.takeBytes())
        ..add(end.buffer.asUint8List())
        ..add(zipComment))
      .takeBytes();
}

Uint8List fixtureZip({
  Uint8List? plan,
  Uint8List? photo,
  Map<String, dynamic>? manifest,
  Uint8List? manifestBytes,
  int method = 0,
  int flags = 0,
}) {
  plan ??= jsonBytes(zipPlanFixture());
  return testZip([
    TestZipEntry(
      'manifest.json',
      manifestBytes ?? jsonBytes(manifest ?? zipManifest(plan, photo)),
      method: method,
      flags: flags,
    ),
    TestZipEntry('plan.json', plan, method: method, flags: flags),
    if (photo != null)
      TestZipEntry('photo.jpg', photo, method: method, flags: flags),
  ]);
}

int read16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);
int read32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);
void put16(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.little);
void put32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
int centralOffset(Uint8List bytes) => read32(bytes, bytes.length - 6);

// A raw Deflate stream made of explicit uncompressed blocks, independent of
// encoder heuristics. Last block's BFINAL bit can deliberately be omitted.
Uint8List rawBlocks(
  Uint8List bytes, {
  int blockSize = 65535,
  bool finalBit = true,
}) {
  final out = BytesBuilder(copy: false);
  for (var start = 0; start < bytes.length; start += blockSize) {
    final end = (start + blockSize).clamp(0, bytes.length);
    final size = end - start;
    out.add([
      end == bytes.length && finalBit ? 1 : 0,
      size & 255,
      size >> 8,
      (~size) & 255,
      ((~size) >> 8) & 255,
    ]);
    out.add(Uint8List.sublistView(bytes, start, end));
  }
  return out.takeBytes();
}
