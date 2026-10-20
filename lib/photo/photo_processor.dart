import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum PhotoIssue {
  cancelled,
  unsupported,
  inputLimit,
  invalidImage,
  outputLimit,
  unsafePath,
  busy,
}

class PhotoFailure implements Exception {
  const PhotoFailure(this.issue);
  final PhotoIssue issue;
  @override
  String toString() => 'PhotoFailure(${issue.name})';
}

/// Deployment limits must be supplied explicitly. Desktop measurements do not
/// establish safe Android/iOS limits; there is intentionally no production default.
class PhotoInputLimits {
  const PhotoInputLimits({
    required this.maxFileBytes,
    required this.maxJpegPixels,
    required this.maxPngPixels,
    required this.maxDimension,
  }) : assert(maxFileBytes > 0),
       assert(maxJpegPixels > 0),
       assert(maxPngPixels > 0),
       assert(maxDimension > 0);
  final int maxFileBytes;
  final int maxJpegPixels;
  final int maxPngPixels;
  final int maxDimension;
}

class PhotoCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const PhotoFailure(PhotoIssue.cancelled);
  }
}

abstract interface class PhotoProcessor {
  Future<Uint8List> process(String sourcePath, PhotoCancellation cancellation);
  Future<void> validate(Uint8List jpeg);
}

/// One conversion at a time, including cancelled/superseded requests. The input
/// path, not the input byte buffer, crosses the isolate boundary. Cancellation
/// kills the worker; results are transferred without another byte-buffer copy.
class DartPhotoProcessor implements PhotoProcessor {
  DartPhotoProcessor(this.limits);
  final PhotoInputLimits limits;
  Future<void> _tail = Future.value();
  static const maxOutputBytes = 3 * 1024 * 1024;
  static const maxOutputDimension = 1600;

  @override
  Future<Uint8List> process(
    String sourcePath,
    PhotoCancellation cancellation,
  ) async {
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    await previous;
    final messages = ReceivePort();
    Isolate? worker;
    try {
      cancellation.check();
      worker = await Isolate.spawn(
        _convertWorker,
        (messages.sendPort, sourcePath, limits),
        onError: messages.sendPort,
        onExit: messages.sendPort,
      );
      final message = await Future.any<Object?>([
        messages.first,
        cancellation.cancelled.then<Object?>((_) => PhotoIssue.cancelled),
      ]);
      cancellation.check();
      if (message is PhotoIssue) throw PhotoFailure(message);
      if (message is! TransferableTypedData) {
        throw const PhotoFailure(PhotoIssue.invalidImage);
      }
      return message.materialize().asUint8List();
    } finally {
      worker?.kill(priority: Isolate.immediate);
      messages.close();
      finished.complete();
    }
  }

  @override
  Future<void> validate(Uint8List jpeg) async {
    // Bound before copying to the isolate, including when used with fake I/O.
    if (jpeg.length > maxOutputBytes) {
      throw const PhotoFailure(PhotoIssue.outputLimit);
    }
    await Isolate.run(() => validatePhotoJpeg(jpeg));
  }
}

void _convertWorker((SendPort, String, PhotoInputLimits) request) {
  final (reply, path, limits) = request;
  try {
    reply.send(TransferableTypedData.fromList([_convertFile(path, limits)]));
  } on PhotoFailure catch (error) {
    reply.send(error.issue);
  } catch (_) {
    reply.send(PhotoIssue.invalidImage);
  }
}

Uint8List _convertFile(String path, PhotoInputLimits limits) {
  if (limits.maxFileBytes <= 0 ||
      limits.maxJpegPixels <= 0 ||
      limits.maxPngPixels <= 0 ||
      limits.maxDimension <= 0) {
    throw const PhotoFailure(PhotoIssue.inputLimit);
  }
  final file = File(path);
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const PhotoFailure(PhotoIssue.unsafePath);
  }
  final input = file.openSync();
  late Uint8List bytes;
  try {
    final length = input.lengthSync();
    if (length <= 0 || length > limits.maxFileBytes) {
      throw const PhotoFailure(PhotoIssue.inputLimit);
    }
    // Read at most the inspected length, even if the source grows concurrently.
    bytes = input.readSync(length);
    if (bytes.length != length || input.lengthSync() != length) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
  } finally {
    input.closeSync();
  }
  late img.Image? decoded;
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    final info = img.JpegDecoder().startDecode(bytes);
    if (info == null) throw const PhotoFailure(PhotoIssue.invalidImage);
    _checkDimensions(info.width, info.height, limits.maxJpegPixels, limits);
    final scale = jpegDecodeScale(info.width, info.height);
    decoded = img.JpegDecoder(
      maxPixels: limits.maxJpegPixels,
      scale: scale,
    ).decode(bytes);
  } else if (_isPng(bytes)) {
    // Inspect chunks before PngDecoder: compressed ancillary metadata can inflate
    // independently of pixel limits. Pass only pixel chunks; inspect bounded
    // uncompressed EXIF separately for the scalar orientation value.
    final (pixelsOnly, orientation) = _safePng(bytes, limits);
    decoded = img.PngDecoder(maxPixels: limits.maxPngPixels).decode(pixelsOnly);
    if (decoded != null && orientation != 1) {
      decoded.exif.imageIfd.orientation = orientation;
    }
  } else {
    throw const PhotoFailure(PhotoIssue.unsupported);
  }
  if (decoded == null || decoded.numFrames != 1) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  // image 4.12.0's JPEG decoder already bakes orientation and clears its tag.
  // PNG EXIF is not read by PngDecoder; apply its bounded header value here.
  // copyResize then sees no remaining tag and cannot apply it twice.
  var oriented = decoded.exif.imageIfd.hasOrientation
      ? img.bakeOrientation(decoded)
      : decoded;
  // Composite BEFORE interpolation so invisible RGB values cannot bleed into
  // visible edge pixels when shrinking. Mutate only the decoded buffer, never
  // the source file; this avoids an extra full-size RGB allocation for PNG.
  final palette = oriented.palette;
  if (palette != null && palette.numChannels == 4) {
    final maximum = palette.maxChannelValue;
    for (var index = 0; index < palette.numColors; index++) {
      final alpha = palette.getAlpha(index) / maximum;
      palette.setRgba(
        index,
        (palette.getRed(index) * alpha + maximum * (1 - alpha)).round(),
        (palette.getGreen(index) * alpha + maximum * (1 - alpha)).round(),
        (palette.getBlue(index) * alpha + maximum * (1 - alpha)).round(),
        maximum,
      );
    }
  }
  if (palette == null) {
    for (final pixel in oriented) {
      final alpha = pixel.aNormalized;
      if (alpha == 1) continue;
      final red = pixel.rNormalized * alpha + 1 - alpha;
      final green = pixel.gNormalized * alpha + 1 - alpha;
      final blue = pixel.bNormalized * alpha + 1 - alpha;
      pixel
        ..rNormalized = red
        ..gNormalized = green
        ..bNormalized = blue
        ..aNormalized = 1;
    }
  }
  final longest = math.max(oriented.width, oriented.height);
  if (longest > DartPhotoProcessor.maxOutputDimension) {
    oriented = img.copyResize(
      oriented,
      width: math.max(1, (oriented.width * 1600 / longest).round()),
      height: math.max(1, (oriented.height * 1600 / longest).round()),
      interpolation: img.Interpolation.average,
    );
  }
  // Fresh RGB image: no EXIF, ICC, text, source thumbnails or other metadata.
  // Blend normalized alpha, including 16-bit and palette PNG inputs.
  final clean = img.Image(
    width: oriented.width,
    height: oriented.height,
    numChannels: 3,
  );
  final grayscale = !oriented.hasPalette && oriented.numChannels == 1;
  for (final pixel in oriented) {
    final alpha = pixel.aNormalized;
    final green = grayscale ? pixel.rNormalized : pixel.gNormalized;
    final blue = grayscale ? pixel.rNormalized : pixel.bNormalized;
    clean.setPixelRgb(
      pixel.x,
      pixel.y,
      (255 * (pixel.rNormalized * alpha + 1 - alpha)).round(),
      (255 * (green * alpha + 1 - alpha)).round(),
      (255 * (blue * alpha + 1 - alpha)).round(),
    );
  }
  final jpeg = img.encodeJpg(clean, quality: 85);
  validatePhotoJpeg(jpeg);
  return jpeg;
}

/// Largest reduction that still retains at least 1600 pixels on the long edge.
int jpegDecodeScale(int width, int height) {
  final longest = math.max(width, height);
  for (final scale in [8, 4, 2]) {
    if (longest ~/ scale >= 1600) return scale;
  }
  return 1;
}

void _checkDimensions(int w, int h, int maxPixels, PhotoInputLimits limits) {
  if (w <= 0 ||
      h <= 0 ||
      w > limits.maxDimension ||
      h > limits.maxDimension ||
      w * h > maxPixels) {
    throw const PhotoFailure(PhotoIssue.inputLimit);
  }
}

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    List.generate(8, (i) => bytes[i]).join(',') == '137,80,78,71,13,10,26,10';

final _pngCrcTable = Uint32List.fromList(
  List.generate(256, (value) {
    var crc = value;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
    return crc;
  }),
);

(Uint8List, int) _safePng(Uint8List bytes, PhotoInputLimits limits) {
  final data = ByteData.sublistView(bytes);
  final output = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(bytes, 0, 8));
  var position = 8;
  var header = false;
  var imageData = false;
  var orientation = 1;
  var hasExif = false;
  while (position + 12 <= bytes.length) {
    final length = data.getUint32(position);
    final end = position + 12 + length;
    if (end > bytes.length) throw const PhotoFailure(PhotoIssue.invalidImage);
    var crc = 0xffffffff;
    for (var i = position + 4; i < end - 4; i++) {
      crc = _pngCrcTable[(crc ^ bytes[i]) & 255] ^ (crc >>> 8);
    }
    if ((crc ^ 0xffffffff) != data.getUint32(end - 4)) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    final type = String.fromCharCodes(
      bytes.sublist(position + 4, position + 8),
    );
    if (!header && type != 'IHDR') {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    if (type == 'acTL' || type == 'fcTL' || type == 'fdAT') {
      throw const PhotoFailure(PhotoIssue.unsupported);
    }
    if (type == 'IHDR') {
      if (header || length != 13) {
        throw const PhotoFailure(PhotoIssue.invalidImage);
      }
      _checkDimensions(
        data.getUint32(position + 8),
        data.getUint32(position + 12),
        limits.maxPngPixels,
        limits,
      );
      header = true;
    }
    if (type == 'IDAT') imageData = true;
    if (type == 'eXIf') {
      if (hasExif || length > 65536) {
        throw const PhotoFailure(PhotoIssue.inputLimit);
      }
      hasExif = true;
      orientation = _tiffOrientation(
        Uint8List.sublistView(bytes, position + 8, end - 4),
      );
    } else if (['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND'].contains(type)) {
      output.add(Uint8List.sublistView(bytes, position, end));
    } else if ((bytes[position + 4] & 32) == 0) {
      throw const PhotoFailure(PhotoIssue.unsupported);
    }
    if (type == 'IEND') {
      if (length != 0 || !imageData || end != bytes.length) {
        throw const PhotoFailure(PhotoIssue.invalidImage);
      }
      return (output.takeBytes(), orientation);
    }
    position = end;
  }
  throw const PhotoFailure(PhotoIssue.invalidImage);
}

// Only read the scalar IFD0 Orientation; never follow arbitrary EXIF pointers or
// copy private metadata into the pixel decoder. TIFF offsets are chunk-relative.
int _tiffOrientation(Uint8List bytes) {
  if (bytes.length < 8) throw const PhotoFailure(PhotoIssue.invalidImage);
  final endian = bytes[0] == 0x49 && bytes[1] == 0x49
      ? Endian.little
      : bytes[0] == 0x4d && bytes[1] == 0x4d
      ? Endian.big
      : null;
  if (endian == null) throw const PhotoFailure(PhotoIssue.invalidImage);
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(2, endian) != 42) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  final offset = data.getUint32(4, endian);
  if (offset < 8 || offset + 2 > bytes.length) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  final count = data.getUint16(offset, endian);
  if (offset + 2 + count * 12 + 4 > bytes.length) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  for (var i = 0; i < count; i++) {
    final entry = offset + 2 + i * 12;
    if (data.getUint16(entry, endian) != 274) continue;
    if (data.getUint16(entry + 2, endian) != 3 ||
        data.getUint32(entry + 4, endian) != 1) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    final orientation = data.getUint16(entry + 8, endian);
    if (orientation < 1 || orientation > 8) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    return orientation;
  }
  return 1;
}

/// Independent JPEG marker policy plus full decode. Source EXIF/XMP/ICC, comments
/// and trailing data are rejected rather than trusting an encoder's defaults.
void validatePhotoJpeg(Uint8List bytes) {
  try {
    _validatePhotoJpeg(bytes);
  } on img.ImageException {
    // Decoder corruption is part of the photo read contract. Programming errors
    // such as StateError are deliberately not converted or swallowed here.
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
}

void _validatePhotoJpeg(Uint8List bytes) {
  if (bytes.length > DartPhotoProcessor.maxOutputBytes) {
    throw const PhotoFailure(PhotoIssue.outputLimit);
  }
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  var position = 2;
  var ended = false;
  while (position < bytes.length) {
    if (bytes[position++] != 0xff) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    while (position < bytes.length && bytes[position] == 0xff) {
      position++;
    }
    if (position >= bytes.length) break;
    final marker = bytes[position++];
    if (marker == 0xd9) {
      ended = position == bytes.length;
      break;
    }
    if (marker == 0xfe || (marker >= 0xe1 && marker <= 0xef)) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    if (position + 2 > bytes.length) break;
    final length = bytes[position] * 256 + bytes[position + 1];
    if (length < 2 || position + length > bytes.length) break;
    // JFIF without a thumbnail is the sole permitted APP marker.
    if (marker == 0xe0 &&
        (length != 16 ||
            String.fromCharCodes(bytes.sublist(position + 2, position + 7)) !=
                'JFIF\u0000' ||
            bytes[position + 14] != 0 ||
            bytes[position + 15] != 0)) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    position += length;
    if (marker == 0xda) {
      while (position + 1 < bytes.length) {
        if (bytes[position] != 0xff) {
          position++;
          continue;
        }
        final next = bytes[position + 1];
        if (next == 0 || (next >= 0xd0 && next <= 0xd7)) {
          position += 2;
          continue;
        }
        break;
      }
    }
  }
  if (!ended) throw const PhotoFailure(PhotoIssue.invalidImage);
  final info = img.JpegDecoder().startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > 1600 ||
      info.height > 1600) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
  final decoded = img.JpegDecoder(maxPixels: 1600 * 1600).decode(bytes);
  if (decoded == null || !decoded.exif.isEmpty) {
    throw const PhotoFailure(PhotoIssue.invalidImage);
  }
}
