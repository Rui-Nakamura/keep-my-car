import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/features/home/presentation/home_car_photo.dart';
import 'package:keep_my_car/photo/photo_library.dart';

import 'photo/photo_test_support.dart';

class ControlledPhotos extends PhotoLibrary {
  ControlledPhotos(this.onRead)
    : super(storage: MemoryPhotos(), processor: FakeProcessor());
  final Future<Uint8List?> Function(String) onRead;
  final reads = <String>[];

  @override
  Future<Uint8List?> read(String id) {
    reads.add(id);
    return onRead(id);
  }
}

Future<void> showPhoto(WidgetTester tester, String? id, PhotoLibrary? photos) =>
    tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 180,
          child: HomeCarPhoto(photoId: id, library: photos),
        ),
      ),
    );

Future<void> finishImage(WidgetTester tester) async {
  final provider = tester.widget<Image>(find.byType(Image)).image;
  await tester.runAsync(() async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    final listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _, StackTrace? _) {
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    await done.future;
    stream.removeListener(listener);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unset and unconfigured photos never start a read', (
    tester,
  ) async {
    final photos = ControlledPhotos((_) async => smallJpeg());
    await showPhoto(tester, null, photos);
    expect(find.byKey(const ValueKey('home-photo-unset')), findsOneWidget);
    expect(photos.reads, isEmpty);
    await showPhoto(tester, photoA, null);
    expect(
      find.byKey(const ValueKey('home-photo-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets(
    'loading resolves to a validated stored JPEG; rebuild does not reread',
    (tester) async {
      final ready = Completer<Uint8List?>();
      final jpeg = smallJpeg();
      final photos = ControlledPhotos((_) => ready.future);
      await showPhoto(tester, photoA, photos);
      expect(find.byKey(const ValueKey('home-photo-loading')), findsOneWidget);
      ready.complete(jpeg);
      await tester.pumpAndSettle();
      await finishImage(tester);
      expect(tester.widget<Image>(find.byType(Image)).semanticLabel, '愛車の写真');
      await showPhoto(tester, photoA, photos);
      await tester.pumpAndSettle();
      expect(photos.reads, [photoA]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in ['missing', 'corrupt', 'io']) {
    testWidgets('existing read contract supplies safe fallback for $failure', (
      tester,
    ) async {
      final storage = MemoryPhotos();
      if (failure == 'corrupt') {
        storage.files[photoA] = Uint8List.fromList([1, 2, 3]);
      }
      final photos = failure == 'io'
          ? PhotoLibrary(
              storage: _UnreadablePhotos(),
              processor: FakeProcessor(),
            )
          : PhotoLibrary(storage: storage, processor: FakeProcessor());
      await showPhoto(tester, photoA, photos);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-photo-unavailable')),
        findsOneWidget,
      );
      expect(storage.files.keys, failure == 'corrupt' ? [photoA] : isEmpty);
      expect(storage.sweeps, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unexpected read errors are diagnosed once and have a safe UI', (
    tester,
  ) async {
    final photos = ControlledPhotos(
      (_) => Future.error(StateError('read bug')),
    );
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await showPhoto(tester, photoA, photos);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-photo-error')), findsOneWidget);
      expect(errors.single.exception, isA<StateError>());
      await showPhoto(tester, photoA, photos);
      await tester.pumpAndSettle();
      expect(errors, hasLength(1));
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('image codec failure uses the decode fallback', (tester) async {
    final photos = ControlledPhotos((_) async => Uint8List.fromList([1, 2, 3]));
    await showPhoto(tester, photoA, photos);
    await tester.pumpAndSettle();
    await finishImage(tester);
    expect(
      find.byKey(const ValueKey('home-photo-decode-error')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ID change clears old pixels and ignores late completion', (
    tester,
  ) async {
    final old = Completer<Uint8List?>();
    final next = Completer<Uint8List?>();
    final photos = ControlledPhotos(
      (id) => id == photoA ? old.future : next.future,
    );
    await showPhoto(tester, photoA, photos);
    await showPhoto(tester, photoB, photos);
    old.complete(smallJpeg());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-photo-loading')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    next.complete(null);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-photo-unavailable')),
      findsOneWidget,
    );
    expect(photos.reads, [photoA, photoB]);
  });

  testWidgets('replacing Library at the same ID cannot retain its old image', (
    tester,
  ) async {
    final first = ControlledPhotos((_) async => smallJpeg());
    final next = Completer<Uint8List?>();
    final second = ControlledPhotos((_) => next.future);
    await showPhoto(tester, photoA, first);
    await tester.pumpAndSettle();
    await finishImage(tester);
    await showPhoto(tester, photoA, second);
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('home-photo-loading')), findsOneWidget);
    next.complete(null);
    await tester.pumpAndSettle();
    expect(first.reads, [photoA]);
    expect(second.reads, [photoA]);
    await showPhoto(tester, null, second);
    expect(find.byKey(const ValueKey('home-photo-unset')), findsOneWidget);
  });

  testWidgets('loaded photo ID change clears old pixels while loading', (
    tester,
  ) async {
    final next = Completer<Uint8List?>();
    final photos = ControlledPhotos(
      (id) async => id == photoA ? smallJpeg() : next.future,
    );
    await showPhoto(tester, photoA, photos);
    await tester.pumpAndSettle();
    await finishImage(tester);
    await showPhoto(tester, photoB, photos);
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('home-photo-loading')), findsOneWidget);
    next.complete(null);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-photo-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('completion after disposal does not update State', (
    tester,
  ) async {
    final ready = Completer<Uint8List?>();
    final photos = ControlledPhotos((_) => ready.future);
    await showPhoto(tester, photoA, photos);
    await tester.pumpWidget(const SizedBox());
    ready.complete(smallJpeg());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _UnreadablePhotos extends MemoryPhotos {
  @override
  Future<Uint8List?> read(String id) async =>
      throw const FileSystemException('read failed');
}
