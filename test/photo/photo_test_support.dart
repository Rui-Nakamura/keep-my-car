import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:keep_my_car/photo/photo_file_storage.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

const photoA = '550e8400-e29b-41d4-a716-446655440000';
const photoB = '550e8400-e29b-41d4-a716-446655440001';
const photoC = '550e8400-e29b-41d4-a716-446655440002';
const photoD = '550e8400-e29b-41d4-a716-446655440003';

Uint8List smallJpeg() => img.encodeJpg(img.Image(width: 8, height: 8));

// Valid markers/lengths and dimensions, but an impossible JPEG sampling factor.
// This reaches pixel decoding rather than merely failing the marker validator.
Uint8List corruptJpegScan() {
  final bytes = smallJpeg();
  for (var i = 2; i + 11 < bytes.length; i++) {
    if (bytes[i] == 0xff && bytes[i + 1] == 0xc0) {
      bytes[i + 11] = 0;
      return bytes;
    }
  }
  throw StateError('Fixture has no SOF0');
}

class FakeProcessor implements PhotoProcessor {
  Future<Uint8List> Function(String, PhotoCancellation)? onProcess;
  FutureOr<void> Function(Uint8List, int)? onValidate;
  int validations = 0;
  final paths = <String>[];
  @override
  Future<Uint8List> process(String path, PhotoCancellation cancellation) async {
    paths.add(path);
    return onProcess == null
        ? smallJpeg()
        : await onProcess!(path, cancellation);
  }

  @override
  Future<void> validate(Uint8List jpeg) async {
    validations++;
    await onValidate?.call(jpeg, validations);
    validatePhotoJpeg(jpeg);
  }
}

class MemoryPhotos implements PhotoFileStorage {
  final files = <String, Uint8List>{};
  final sweeps = <Set<String>>[];
  Future<void> Function()? onWrite;
  Future<void> Function()? onCleanup;
  @override
  Future<void> writeNew(
    String id,
    Uint8List jpeg,
    PhotoProcessor validator,
  ) async {
    await onWrite?.call();
    if (files.containsKey(id)) throw StateError('collision');
    await validator.validate(jpeg);
    files[id] = jpeg;
  }

  @override
  Future<Uint8List?> read(String id) async => files[id];
  @override
  Future<void> cleanup(Set<String> protectedIds) async {
    sweeps.add(protectedIds.toSet());
    await onCleanup?.call();
    files.removeWhere((id, _) => !protectedIds.contains(id));
  }
}
