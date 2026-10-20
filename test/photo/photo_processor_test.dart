import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:keep_my_car/photo/photo_processor.dart';

import 'photo_test_support.dart' show corruptJpegScan;

// Test-only JPEG walker. It inspects the actual byte stream, including markers
// after entropy data; it neither calls nor copies the production validator.
List<({int marker, int offset, Uint8List payload})> jpegMarkers(
  Uint8List bytes,
) {
  final result = <({int marker, int offset, Uint8List payload})>[];
  if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) {
    throw StateError('Not a JPEG');
  }
  var pos = 2;
  var entropy = false;
  while (pos < bytes.length) {
    if (entropy) {
      if (bytes[pos++] != 255) continue;
      while (pos < bytes.length && bytes[pos] == 255) {
        pos++;
      }
      if (pos == bytes.length) break;
      if (bytes[pos] == 0 || (bytes[pos] >= 208 && bytes[pos] <= 215)) {
        pos++;
        continue;
      }
      pos--;
      entropy = false;
    }
    final offset = pos;
    if (bytes[pos++] != 255) throw StateError('Missing marker');
    while (pos < bytes.length && bytes[pos] == 255) {
      pos++;
    }
    if (pos == bytes.length) break;
    final marker = bytes[pos++];
    if (marker == 217) {
      if (pos != bytes.length) throw StateError('Trailing bytes');
      result.add((marker: marker, offset: offset, payload: Uint8List(0)));
      return result;
    }
    if (pos + 2 > bytes.length) break;
    final length = bytes[pos] * 256 + bytes[pos + 1];
    if (length < 2 || pos + length > bytes.length) {
      throw StateError('Invalid segment length');
    }
    result.add((
      marker: marker,
      offset: offset,
      payload: Uint8List.sublistView(bytes, pos + 2, pos + length),
    ));
    pos += length;
    entropy = marker == 218;
  }
  throw StateError('No EOI');
}

List<int> jpegSegment(int marker, List<int> payload) => [
  255,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 255,
  ...payload,
];

Uint8List withJpegSegment(Uint8List jpeg, int marker, List<int> payload) =>
    Uint8List.fromList([
      ...jpeg.take(2),
      ...jpegSegment(marker, payload),
      ...jpeg.skip(2),
    ]);

void expectPrivateMetadataAbsent(Uint8List bytes) {
  final markers = jpegMarkers(bytes);
  expect(markers.any((m) => m.marker == 192), true);
  expect(markers.any((m) => m.marker == 218), true);
  expect(markers.last.marker, 217);
  expect(
    markers.where(
      (m) => (m.marker >= 225 && m.marker <= 239) || m.marker == 254,
    ),
    isEmpty,
  );
  for (final part in markers.where((m) => m.marker == 224)) {
    expect(part.payload.length, 14);
    expect(part.payload.take(5), [74, 70, 73, 70, 0]);
    expect(part.payload.skip(12), [0, 0]); // No embedded thumbnail.
  }
}

List<int> pngChunk(String type, List<int> data) {
  final payload = [...type.codeUnits, ...data];
  var crc = 0xffffffff;
  for (final byte in payload) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  final length = ByteData(4)..setUint32(0, data.length);
  final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
  return [
    ...length.buffer.asUint8List(),
    ...payload,
    ...checksum.buffer.asUint8List(),
  ];
}

List<String> pngChunkTypes(Uint8List bytes) {
  final types = <String>[];
  for (var pos = 8; pos < bytes.length;) {
    final size = ByteData.sublistView(bytes).getUint32(pos);
    types.add(String.fromCharCodes(bytes.sublist(pos + 4, pos + 8)));
    pos += size + 12;
    if (pos > bytes.length) throw StateError('Bad fixture chunk');
  }
  return types;
}

// Fresh RGB reference for the scale-wiring test, independent of process().
Uint8List encodeRgb(img.Image image) {
  final clean = img.Image(
    width: image.width,
    height: image.height,
    numChannels: 3,
  );
  for (final p in image) {
    clean.setPixelRgb(p.x, p.y, p.r, p.g, p.b);
  }
  return img.encodeJpg(clean, quality: 85);
}

// Test profile, NOT an accepted production/device safety limit.
const testLimits = PhotoInputLimits(
  maxFileBytes: 64 * 1024 * 1024,
  maxJpegPixels: 64 * 1000 * 1000,
  maxPngPixels: 24 * 1000 * 1000,
  maxDimension: 16000,
);

img.Image colorGrid({bool alpha = false}) {
  final image = img.Image(width: 80, height: 48, numChannels: alpha ? 4 : 3);
  for (final p in image) {
    image.setPixelRgba(
      p.x,
      p.y,
      p.x < 40 ? 220 : 20,
      p.y < 24 ? 200 : 30,
      p.x < 40 ? 20 : 220,
      255,
    );
  }
  return image;
}

// Build a PNG eXIf chunk independently of the library's PNG encoder (which does
// not preserve EXIF). CRC uses the PNG polynomial, not production parsing code.
Uint8List pngWithExif(img.Image image, int orientation) {
  final png = img.encodePng(image);
  final tiff = ByteData(26)
    ..setUint8(0, 0x49)
    ..setUint8(1, 0x49)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 274, Endian.little)
    ..setUint16(12, 3, Endian.little)
    ..setUint32(14, 1, Endian.little)
    ..setUint16(18, orientation, Endian.little);
  final payload = [...'eXIf'.codeUnits, ...tiff.buffer.asUint8List()];
  var crc = 0xffffffff;
  for (final byte in payload) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  final chunk = ByteData(12 + 26)
    ..setUint32(0, 26)
    ..setUint32(34, crc ^ 0xffffffff);
  final bytes = chunk.buffer.asUint8List()..setRange(4, 34, payload);
  return Uint8List.fromList([
    ...png.sublist(0, 33),
    ...bytes,
    ...png.sublist(33),
  ]);
}

void main() {
  late Directory directory;
  late DartPhotoProcessor processor;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kmc-photo-test-');
    processor = DartPhotoProcessor(testLimits);
  });
  tearDown(() async {
    expect(
      directory.absolute.path,
      startsWith(Directory.systemTemp.absolute.path),
    );
    await directory.delete(recursive: true);
  });

  Future<File> source(List<int> bytes) =>
      File('${directory.path}/source').writeAsBytes(bytes);
  Future<Uint8List> convert(List<int> bytes) async =>
      processor.process((await source(bytes)).path, PhotoCancellation());

  test(
    'independent byte inspection proves EXIF GPS XMP ICC COM removal',
    () async {
      final image = colorGrid();
      image.exif.imageIfd['Make'] = img.IfdValueAscii('Private camera');
      image.exif.gpsIfd[1] = img.IfdValueAscii('N');
      image.exif.gpsIfd[2] = img.IfdValueRational(35, 1);
      var input = img.encodeJpg(image);
      input = withJpegSegment(input, 225, [
        ...'http://ns.adobe.com/xap/1.0/'.codeUnits,
        0,
        ...'<x:xmpmeta>Private GPS 35,139</x:xmpmeta>'.codeUnits,
      ]);
      final profile = Uint8List(128);
      ByteData.sublistView(profile).setUint32(0, profile.length);
      profile.setRange(36, 40, 'acsp'.codeUnits);
      input = withJpegSegment(input, 226, [
        ...'ICC_PROFILE'.codeUnits,
        0,
        1,
        1,
        ...profile,
      ]);
      input = withJpegSegment(input, 254, 'Private comment'.codeUnits);
      final parts = jpegMarkers(input);
      expect(parts.where((p) => p.marker == 225).length, 2);
      expect(parts.any((p) => p.marker == 226), true);
      expect(parts.any((p) => p.marker == 254), true);
      final exif = img.decodeJpg(input)!.exif;
      expect(exif.gpsIfd[1].toString(), contains('N'));
      final file = await source(input);
      final output = await processor.process(file.path, PhotoCancellation());
      expectPrivateMetadataAbsent(output);
      expect(String.fromCharCodes(output), isNot(contains('Private')));
      expect(await file.readAsBytes(), input);
    },
  );

  test(
    'PNG text compressed ICC and EXIF GPS do not reach output metadata',
    () async {
      final png = img.encodePng(colorGrid());
      final input = Uint8List.fromList([
        ...png.take(33),
        ...pngChunk('tEXt', 'Location\u0000Private GPS 35,139'.codeUnits),
        ...pngChunk('iCCP', [
          ...'Private profile'.codeUnits,
          0,
          0,
          ...ZLibEncoder().convert(List<int>.filled(128, 42)),
        ]),
        ...png.skip(33),
      ]);
      expect(pngChunkTypes(input), containsAll(['tEXt', 'iCCP']));
      // A full GPS-bearing eXIf block is also passed through the PNG sanitizer.
      final gpsImage = colorGrid()..exif.gpsIfd[1] = img.IfdValueAscii('N');
      final gps = jpegMarkers(img.encodeJpg(gpsImage))
          .firstWhere((p) => p.marker == 225)
          .payload;
      final withGps = Uint8List.fromList([
        ...input.take(33),
        ...pngChunk('eXIf', gps.sublist(6)),
        ...input.skip(33),
      ]);
      expect(pngChunkTypes(withGps).where((t) => t == 'eXIf').length, 1);
      expectPrivateMetadataAbsent(await convert(withGps));
    },
  );

  test('APP2 COM and malformed JFIF thumbnail are rejected', () {
    final clean = img.encodeJpg(colorGrid());
    for (final marker in [226, 254]) {
      final bad = withJpegSegment(clean, marker, 'Private'.codeUnits);
      expect(jpegMarkers(bad).any((p) => p.marker == marker), true);
      expect(() => validatePhotoJpeg(bad), throwsA(isA<PhotoFailure>()));
    }
    final bad = Uint8List.fromList(clean);
    final app0 = jpegMarkers(bad).firstWhere((p) => p.marker == 224);
    bad[app0.offset + 4 + 12] =
        1; // Claims a thumbnail with no thumbnail bytes.
    expect(jpegMarkers(bad).firstWhere((p) => p.marker == 224).payload[12], 1);
    expect(() => validatePhotoJpeg(bad), throwsA(isA<PhotoFailure>()));
  });

  test('marker-valid invalid JPEG is normalized from ImageException', () async {
    final corrupt = corruptJpegScan();
    expect(jpegMarkers(corrupt).last.marker, 217);
    expect(
      () => img.JpegDecoder().decode(corrupt),
      throwsA(isA<img.ImageException>()),
    );
    expect(
      () => validatePhotoJpeg(corrupt),
      throwsA(
        isA<PhotoFailure>().having(
          (e) => e.issue,
          'issue',
          PhotoIssue.invalidImage,
        ),
      ),
    );
    await expectLater(
      processor.validate(corrupt),
      throwsA(isA<PhotoFailure>()),
    );
  });

  test(
    'JPEG exact input limits accept boundary and reject each excess',
    () async {
      final bytes = img.encodeJpg(colorGrid());
      final path = (await source(bytes)).path;
      Future<Uint8List> process({
        int? fileBytes,
        int pixels = 3840,
        int dimension = 80,
      }) => DartPhotoProcessor(
        PhotoInputLimits(
          maxFileBytes: fileBytes ?? bytes.length,
          maxJpegPixels: pixels,
          maxPngPixels: 3840,
          maxDimension: dimension,
        ),
      ).process(path, PhotoCancellation());
      expectPrivateMetadataAbsent(await process());
      for (final failing in [
        () => process(fileBytes: bytes.length - 1),
        () => process(pixels: 3839),
        () => process(dimension: 79),
      ]) {
        await expectLater(
          failing(),
          throwsA(
            isA<PhotoFailure>().having(
              (e) => e.issue,
              'issue',
              PhotoIssue.inputLimit,
            ),
          ),
        );
      }
      expect(img.JpegDecoder(maxPixels: 3840).decode(bytes), isNotNull);
      expect(
        () => img.JpegDecoder(maxPixels: 3839).decode(bytes),
        throwsA(isA<img.ImageException>()),
      );
    },
  );

  test('JPEG zero and oversized header dimensions are rejected', () async {
    for (final dimensions in [(0, 48), (80, 0), (65535, 65535)]) {
      final bytes = img.encodeJpg(colorGrid());
      final sof = jpegMarkers(bytes).firstWhere((m) => m.marker == 192);
      final data = ByteData.sublistView(bytes);
      data.setUint16(sof.offset + 5, dimensions.$2);
      data.setUint16(sof.offset + 7, dimensions.$1);
      await expectLater(convert(bytes), throwsA(isA<PhotoFailure>()));
    }
  });

  test(
    'JPEG scale thresholds and rotated dimensions select exact reduction',
    () {
      for (final entry in {
        1599: 1,
        1600: 1,
        3199: 1,
        3200: 2,
        6399: 2,
        6400: 4,
        12799: 4,
        12800: 8,
        16000: 8,
      }.entries) {
        expect(jpegDecodeScale(entry.key, 48), entry.value);
        expect(jpegDecodeScale(48, entry.key), entry.value);
      }
    },
  );

  for (final orientation in [1, 6]) {
    test(
      'actual reduced JPEG decode wiring Orientation $orientation',
      () async {
        final image = img.Image(width: 3200, height: 64)
          ..exif.imageIfd.orientation = orientation;
        for (final p in image) {
          image.setPixelRgb(
            p.x,
            p.y,
            (p.x * 73 + p.y * 29) % 256,
            (p.x * 19 + p.y * 101) % 256,
            (p.x * 47 + p.y * 53) % 256,
          );
        }
        final input = img.encodeJpg(image, quality: 95);
        final reduced = img.JpegDecoder(scale: 2).decode(input)!;
        expect((
          reduced.width,
          reduced.height,
        ), orientation == 6 ? (32, 1600) : (1600, 32));
        final expected = encodeRgb(reduced);
        final full = img.JpegDecoder().decode(input)!;
        final withoutScale = encodeRgb(
          img.copyResize(
            full,
            width: reduced.width,
            height: reduced.height,
            interpolation: img.Interpolation.average,
          ),
        );
        expect(
          expected,
          isNot(orderedEquals(withoutScale)),
          reason:
              'Fixture must distinguish reduced IDCT from full decode + resize',
        );
        expect(await convert(input), orderedEquals(expected));
      },
    );
  }

  for (var orientation = 1; orientation <= 8; orientation++) {
    test('PNG EXIF Orientation $orientation applied once', () async {
      final original = colorGrid();
      final out = img.decodeJpg(
        await convert(pngWithExif(original, orientation)),
      )!;
      expect((out.width, out.height), orientation >= 5 ? (48, 80) : (80, 48));
      final point = switch (orientation) {
        2 => (69, 10),
        3 => (69, 37),
        4 => (10, 37),
        5 => (10, 10),
        6 => (37, 10),
        7 => (37, 69),
        8 => (10, 69),
        _ => (10, 10),
      };
      final pixel = out.getPixel(point.$1, point.$2);
      expect(pixel.r, closeTo(220, 12));
      expect(pixel.g, closeTo(200, 12));
      expect(pixel.b, closeTo(20, 12));
      expect(out.exif.isEmpty, true);
    });
    test(
      'JPEG Orientation $orientation has correct pixel positions without metadata',
      () async {
        final original = colorGrid()..exif.imageIfd.orientation = orientation;
        original.exif.imageIfd['Make'] = img.IfdValueAscii('Private camera');
        original.exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(
          '2026:10:20 12:00:00',
        );
        original.exif.gpsIfd[1] = img.IfdValueAscii('N');
        original.exif.gpsIfd[2] = img.IfdValueRational(35, 1);
        final encoded = img.encodeJpg(original, quality: 100);
        final file = await source(encoded);
        final before = await file.readAsBytes();
        final out = await processor.process(file.path, PhotoCancellation());
        validatePhotoJpeg(out);
        final actual = img.decodeJpg(out)!;
        // Independent orientation oracle: map three asymmetric source positions.
        (int, int) dest(int x, int y) => switch (orientation) {
          2 => (79 - x, y),
          3 => (79 - x, 47 - y),
          4 => (x, 47 - y),
          5 => (y, x),
          6 => (47 - y, x),
          7 => (47 - y, 79 - x),
          8 => (y, 79 - x),
          _ => (x, y),
        };
        expect(actual.width, orientation >= 5 ? 48 : 80);
        expect(actual.height, orientation >= 5 ? 80 : 48);
        for (final point in [(10, 10), (65, 10), (10, 35)]) {
          final (x, y) = dest(point.$1, point.$2);
          final pixel = actual.getPixel(x, y);
          final expected = original.getPixel(point.$1, point.$2);
          expect(pixel.r, closeTo(expected.r, 12));
          expect(pixel.g, closeTo(expected.g, 12));
          expect(pixel.b, closeTo(expected.b, 12));
        }
        expect(actual.exif.isEmpty, true);
        expect(String.fromCharCodes(out), isNot(contains('Private camera')));
        expect(await file.readAsBytes(), before);
      },
    );
  }

  test('PNG full and half transparency is composited onto white', () async {
    final image = img.Image(width: 64, height: 32, numChannels: 4);
    for (final p in image) {
      image.setPixelRgba(p.x, p.y, 255, 0, 0, p.x < 32 ? 0 : 128);
    }
    final out = img.decodeJpg(await convert(img.encodePng(image)))!;
    final transparent = out.getPixel(10, 10);
    final half = out.getPixel(50, 10);
    expect(transparent.r, closeTo(255, 3));
    expect(transparent.g, closeTo(255, 3));
    expect(transparent.b, closeTo(255, 3));
    expect(half.r, closeTo(255, 5));
    expect(half.g, closeTo(127, 5));
    expect(half.b, closeTo(127, 5));
  });

  test(
    'resize uses long edge 1600 and preserves aspect without upscaling',
    () async {
      final image = img.Image(width: 2000, height: 1000);
      final out = img.decodeJpg(await convert(img.encodeJpg(image)))!;
      expect((out.width, out.height), (1600, 800));
      final small = img.decodeJpg(await convert(img.encodeJpg(colorGrid())))!;
      expect((small.width, small.height), (80, 48));
    },
  );

  test('downscaling transparency does not mix invisible colored pixels', () async {
    final image = img.Image(width: 3200, height: 2, numChannels: 4);
    for (final p in image) {
      image.setPixelRgba(
        p.x,
        p.y,
        p.x.isEven ? 255 : 0,
        0,
        p.x.isEven ? 0 : 255,
        p.x.isEven ? 255 : 0,
      );
    }
    final out = img.decodeJpg(await convert(img.encodePng(image)))!;
    final p = out.getPixel(500, 0);
    // Half opaque red plus half white. The invisible blue contributes nothing.
    expect(p.r, closeTo(255, 5));
    expect(p.g, closeTo(127, 5));
    expect(p.b, closeTo(127, 5));
  });

  for (final channels in [1, 2]) {
    test(
      'grayscale PNG channels=$channels keeps neutral color and alpha',
      () async {
        final image = img.Image(width: 32, height: 32, numChannels: channels);
        for (final p in image) {
          p.r = 128;
          if (channels == 2) p.a = 128;
        }
        final out = img.decodeJpg(await convert(img.encodePng(image)))!;
        final expected = channels == 1 ? 128 : 192;
        final p = out.getPixel(10, 10);
        expect(p.r, closeTo(expected, 4));
        expect(p.g, closeTo(expected, 4));
        expect(p.b, closeTo(expected, 4));
      },
    );
  }

  test('JPEG reductions select 1, 2, 4, 8 while preserving output detail', () {
    expect(
      [
        jpegDecodeScale(1600, 900),
        jpegDecodeScale(4000, 3000),
        jpegDecodeScale(8000, 6000),
        jpegDecodeScale(16000, 9000),
      ],
      [1, 2, 4, 8],
    );
  });

  test('1/8 JPEG decode and Orientation 6 retain long edge detail', () async {
    final image = img.Image(width: 12800, height: 800)
      ..exif.imageIfd.orientation = 6;
    final out = img.decodeJpg(await convert(img.encodeJpg(image)))!;
    expect((out.width, out.height), (100, 1600));
  });

  test('invalid, truncated, HEIC and other formats are rejected', () async {
    for (final bytes in [
      <int>[],
      [1, 2, 3],
      [0xff, 0xd8, 0xff, 0xe0],
      [0, 0, 0, 24, ...'ftypheic'.codeUnits],
      img.encodeGif(colorGrid()),
    ]) {
      await expectLater(convert(bytes), throwsA(isA<PhotoFailure>()));
    }
  });

  test('file limit is checked before reading the encoded buffer', () async {
    final limited = DartPhotoProcessor(
      const PhotoInputLimits(
        maxFileBytes: 16,
        maxJpegPixels: 10000,
        maxPngPixels: 10000,
        maxDimension: 100,
      ),
    );
    final file = await source(img.encodeJpg(colorGrid()));
    await expectLater(
      limited.process(file.path, PhotoCancellation()),
      throwsA(
        isA<PhotoFailure>().having(
          (e) => e.issue,
          'issue',
          PhotoIssue.inputLimit,
        ),
      ),
    );
  });

  test('PNG dimensions are rejected before pixel decode', () async {
    final bytes = img.encodePng(colorGrid());
    ByteData.sublistView(bytes).setUint32(16, 0x7fffffff);
    // Repair IHDR CRC so rejection exercises the dimension guard.
    var crc = 0xffffffff;
    for (final byte in bytes.sublist(12, 29)) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 1 != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
      }
    }
    ByteData.sublistView(bytes).setUint32(29, crc ^ 0xffffffff);
    await expectLater(
      convert(bytes),
      throwsA(
        isA<PhotoFailure>().having(
          (e) => e.issue,
          'issue',
          PhotoIssue.inputLimit,
        ),
      ),
    );
  });

  test('PNG chunk checksum corruption is rejected', () async {
    final png = img.encodePng(colorGrid());
    png[29] ^= 1;
    await expectLater(convert(png), throwsA(isA<PhotoFailure>()));
  });

  test('APNG is rejected before animation decoding', () async {
    final image = colorGrid()..addFrame(colorGrid());
    await expectLater(
      convert(img.encodePng(image)),
      throwsA(isA<PhotoFailure>()),
    );
  });

  test('output validator rejects oversize, metadata, truncation and trailing bytes', () {
    final clean = img.encodeJpg(colorGrid());
    validatePhotoJpeg(clean);
    final private = colorGrid()..exif.gpsIfd[1] = img.IfdValueAscii('N');
    for (final bad in [
      Uint8List(3 * 1024 * 1024 + 1),
      img.encodeJpg(private),
      Uint8List.sublistView(clean, 0, clean.length - 2),
      Uint8List.fromList([...clean, 42]),
    ]) {
      expect(() => validatePhotoJpeg(bad), throwsA(isA<PhotoFailure>()));
    }
  });

  test(
    'cancelled request never starts conversion and subsequent conversion works',
    () async {
      final file = await source(img.encodeJpg(colorGrid()));
      final cancellation = PhotoCancellation()..cancel();
      await expectLater(
        processor.process(file.path, cancellation),
        throwsA(isA<PhotoFailure>()),
      );
      validatePhotoJpeg(
        await processor.process(file.path, PhotoCancellation()),
      );
    },
  );

  test(
    'cancellation while worker is running releases serial conversion queue',
    () async {
      final file = await source(
        img.encodePng(img.Image(width: 2000, height: 2000, numChannels: 4)),
      );
      final cancel = PhotoCancellation();
      final pending = processor.process(file.path, cancel);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      cancel.cancel();
      await expectLater(
        pending,
        throwsA(
          isA<PhotoFailure>().having(
            (e) => e.issue,
            'issue',
            PhotoIssue.cancelled,
          ),
        ),
      );
      validatePhotoJpeg(
        await processor.process(file.path, PhotoCancellation()),
      );
    },
  );

  test(
    'palette PNG transparency is composited without changing palette indices',
    () async {
      final image = img.Image(
        width: 64,
        height: 32,
        numChannels: 4,
        withPalette: true,
      );
      image.palette!.setRgba(0, 0, 0, 255, 0);
      image.palette!.setRgba(1, 255, 0, 0, 128);
      for (final p in image) {
        image.setPixelIndex(p.x, p.y, p.x < 32 ? 0 : 1);
      }
      final out = img.decodeJpg(await convert(img.encodePng(image)))!;
      expect(out.getPixel(10, 10).r, closeTo(255, 4));
      expect(out.getPixel(10, 10).b, closeTo(255, 4));
      expect(out.getPixel(50, 10).r, closeTo(255, 5));
      expect(out.getPixel(50, 10).g, closeTo(127, 5));
    },
  );

  test(
    '16-bit RGBA PNG alpha is normalized before white compositing',
    () async {
      final image = img.Image(
        width: 32,
        height: 32,
        numChannels: 4,
        format: img.Format.uint16,
      );
      for (final p in image) {
        image.setPixelRgba(p.x, p.y, 65535, 0, 0, 32768);
      }
      final out = img.decodeJpg(await convert(img.encodePng(image)))!;
      expect(out.getPixel(10, 10).g, closeTo(127, 5));
    },
  );
}
