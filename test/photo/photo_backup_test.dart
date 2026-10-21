import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/photo/photo_file_storage.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import 'photo_test_support.dart';

void main() {
  test(
    'backup production factory validates JPEG without a raw-input profile',
    () async {
      final photos = PhotoLibrary.backupApplicationSupport();
      expect(photos.processor, isA<StoredJpegProcessor>());
      await photos.processor.validate(smallJpeg());
      await expectLater(
        photos.processor.process('unapproved-input', PhotoCancellation()),
        throwsA(
          isA<PhotoFailure>().having(
            (e) => e.issue,
            'issue',
            PhotoIssue.unsupported,
          ),
        ),
      );
    },
  );

  test('bytes preparation shares ready barrier and lease protection', () async {
    final files = MemoryPhotos();
    final processor = FakeProcessor();
    final library = PhotoLibrary(storage: files, processor: processor);
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onWrite = () async {
      entered.complete();
      await release.future;
    };
    final outer = library.protect(photoA);
    final preparing = library.prepareJpeg(
      photoA,
      smallJpeg(),
      PhotoCancellation(),
    );
    await entered.future;
    var readCompleted = false;
    final reading = library.readForBackup(photoA).then((value) {
      readCompleted = true;
      return value;
    });
    await library.cleanup({});
    expect(files.sweeps.single, contains(photoA));
    expect(readCompleted, false);
    release.complete();
    await preparing;
    expect((await reading).status, BackupPhotoStatus.available);
    expect(processor.paths, isEmpty);
    outer.release();
    await library.cleanup({});
    expect(files.files, isEmpty);
  });

  test('diagnostic JPEG owns immutable data; legacy missing read still returns null', () async {
    final bytes = smallJpeg();
    final files = MemoryPhotos()..files[photoA] = bytes;
    final library = PhotoLibrary(storage: files, processor: FakeProcessor());
    final read = await library.readForBackup(photoA);
    bytes[0] = 0;
    expect(read.jpeg![0], 0xff);
    expect(() => read.jpeg![0] = 0, throwsUnsupportedError);
    expect(await library.read(photoB), null);
    expect(
      (await library.readForBackup(photoB)).status,
      BackupPhotoStatus.missing,
    );
  });

  test(
    'cancelled JPEG preparation does not write; failure releases ready barrier',
    () async {
      final files = MemoryPhotos();
      final library = PhotoLibrary(storage: files, processor: FakeProcessor());
      final cancel = PhotoCancellation()..cancel();
      await expectLater(
        library.prepareJpeg(photoA, smallJpeg(), cancel),
        throwsA(isA<PhotoFailure>()),
      );
      expect(files.files, isEmpty);
      files.onWrite = () async => throw const FileSystemException('injected');
      await expectLater(
        library.prepareJpeg(photoA, smallJpeg(), PhotoCancellation()),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await library.readForBackup(photoA)).status,
        BackupPhotoStatus.missing,
      );
    },
  );

  test(
    'real storage missing paths and invalid path safety have distinct results',
    () async {
      final root = await Directory.systemTemp.createTemp('kmc-zip-photo-');
      try {
        final library = PhotoLibrary(
          storage: IoPhotoFileStorage(directory: () async => root),
          processor: StoredJpegProcessor(),
        );
        expect(
          (await library.readForBackup(photoA)).status,
          BackupPhotoStatus.missing,
        );
        await library.prepareJpeg(photoA, smallJpeg(), PhotoCancellation());
        expect(
          (await library.readForBackup(photoA)).status,
          BackupPhotoStatus.available,
        );
        expect(
          (await library.readForBackup(photoB)).status,
          BackupPhotoStatus.missing,
        );
        final badProvider = PhotoLibrary(
          storage: IoPhotoFileStorage(
            directory: () async => throw const FileSystemException('denied'),
          ),
          processor: StoredJpegProcessor(),
        );
        expect(
          (await badProvider.readForBackup(photoA)).status,
          BackupPhotoStatus.ioFailure,
        );
        await File('${root.path}/photos/$photoB.jpg').create();
        expect(
          (await library.readForBackup(photoB)).status,
          BackupPhotoStatus.corrupt,
        );
        final unsafe = PhotoLibrary(
          storage: IoPhotoFileStorage(
            directory: () async => Directory('${root.path}/photos/$photoB.jpg'),
          ),
          processor: StoredJpegProcessor(),
        );
        expect(
          (await unsafe.readForBackup(photoA)).status,
          BackupPhotoStatus.unsafe,
        );
      } finally {
        final actual = await root.resolveSymbolicLinks();
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        if (!actual.startsWith(
          '$temp${Platform.pathSeparator}kmc-zip-photo-',
        )) {
          throw StateError('Unsafe cleanup');
        }
        await root.delete(recursive: true);
      }
    },
  );
}
