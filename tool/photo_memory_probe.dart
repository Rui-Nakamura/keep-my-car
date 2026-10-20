// Desktop-only reproducible feasibility probe. Not mobile memory acceptance.
// Generate fixtures in a separate process so fixture allocation is excluded from
// each measurement: dart run tool/photo_memory_probe.dart generate <jpeg12|jpeg48|png12>
// Then: dart run tool/photo_memory_probe.dart measure <name> [repeat]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:keep_my_car/photo/photo_processor.dart';

const profile = PhotoInputLimits(
  maxFileBytes: 64 * 1024 * 1024,
  maxJpegPixels: 64 * 1000 * 1000,
  maxPngPixels: 24 * 1000 * 1000,
  maxDimension: 16000,
);

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 ||
      !['jpeg12', 'jpeg48', 'png12'].contains(arguments[1])) {
    throw ArgumentError('generate|measure jpeg12|jpeg48|png12 [repeat]');
  }
  final name = arguments[1];
  final directory = Directory('.dart_tool/photo_probe');
  final file = File('${directory.path}/$name');
  if (arguments[0] == 'generate') {
    await directory.create(recursive: true);
    final image = img.Image(
      width: name == 'jpeg48' ? 8000 : 4000,
      height: name == 'jpeg48' ? 6000 : 3000,
      numChannels: name == 'png12' ? 4 : 3,
    );
    for (final p in image) {
      image.setPixelRgba(
        p.x,
        p.y,
        p.x % 256,
        p.y % 256,
        (p.x + p.y) % 256,
        name == 'png12' ? 128 : 255,
      );
    }
    await file.writeAsBytes(
      name == 'png12'
          ? img.encodePng(image)
          : img.encodeJpg(image, quality: 90),
    );
    stdout.writeln(
      jsonEncode({'generated': name, 'inputBytes': await file.length()}),
    );
    return;
  }
  if (arguments[0] != 'measure') throw ArgumentError('generate|measure');
  final processor = DartPhotoProcessor(profile);
  final records = <Object>[];
  for (
    var iteration = 0;
    iteration < (arguments.length > 2 ? int.parse(arguments[2]) : 1);
    iteration++
  ) {
    final before = ProcessInfo.currentRss;
    var sampledPeak = before;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (ProcessInfo.currentRss > sampledPeak) {
        sampledPeak = ProcessInfo.currentRss;
      }
    });
    final clock = Stopwatch()..start();
    try {
      final bytes = await processor.process(
        file.absolute.path,
        PhotoCancellation(),
      );
      validatePhotoJpeg(bytes);
      final info = img.JpegDecoder().startDecode(bytes)!;
      if (info.width != 1600 || info.height != 1200) {
        throw StateError('unexpected dimensions');
      }
      records.add({
        'iteration': iteration + 1,
        'milliseconds': clock.elapsedMilliseconds,
        'baselineRssBytes': before,
        'sampledPeakRssBytes': sampledPeak,
        'processMaxRssBytes': ProcessInfo.maxRss,
        'outputBytes': bytes.length,
        'outputWidth': info.width,
        'outputHeight': info.height,
      });
    } finally {
      timer.cancel();
    }
  }
  stdout.writeln(
    jsonEncode({
      'case': name,
      'inputBytes': await file.length(),
      'profile': 'desktop feasibility only; no approved device limits',
      'measurements': records,
    }),
  );
}
