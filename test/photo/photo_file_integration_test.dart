import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:keep_my_car/app/persistent_plan_state.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';
import 'package:keep_my_car/photo/photo_file_storage.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import '../persistence_app_support.dart';
import 'photo_processor_test.dart' show testLimits;

void main() {
  test(
    'real input, photo files, JSON Safe Save, restart and backup recovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kmc-photo-integration-',
      );
      final repository = KeepMyCarRepository(
        IoLocalFileStorage(directory: () async => root),
      );
      final library = PhotoLibrary(
        storage: IoPhotoFileStorage(directory: () async => root),
        processor: DartPhotoProcessor(testLimits),
      );
      final state = PersistentPlanState(
        repository: repository,
        referenceMonth: const YearMonth(2026, 9),
        photos: library,
      );
      try {
        await repository.save(sampleSnapshot());
        await state.load();
        expect(state.photoId, null);
        final image = img.Image(width: 64, height: 48, numChannels: 4);
        for (final pixel in image) {
          image.setPixelRgba(pixel.x, pixel.y, 200, 100, 0, 128);
        }
        final source = File('${root.path}/source.png');
        final original = img.encodePng(image);
        await source.writeAsBytes(original);
        expect(await state.changePhoto(source.path), true);
        final first = state.photoId!;
        expect(await library.read(first), isNotNull);
        expect(await state.changePhoto(source.path), true);
        final second = state.photoId!;
        expect(second, isNot(first));
        await state.load();
        expect(state.photoId, second);
        expect(await File('${root.path}/photos/$first.jpg').exists(), true);
        await File('${root.path}/keep_my_car.json').writeAsString('{corrupt');
        await state.load();
        expect(state.phase, StartupPhase.recovered);
        expect(state.photoId, first);
        expect(await library.read(first), isNotNull);
        expect(await state.cleanupPhotos(), false);
        await state.saveCarName('explicit save after recovery');
        expect(await File('${root.path}/photos/$second.jpg').exists(), false);
        expect(await library.read(first), isNotNull);
        expect(await source.readAsBytes(), original);
      } finally {
        state.dispose();
        expect(
          root.absolute.path,
          startsWith(Directory.systemTemp.absolute.path),
        );
        await root.delete(recursive: true);
      }
    },
  );
}
