import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/photo/photo_file_storage.dart';
import 'package:keep_my_car/photo/photo_library.dart';
import 'package:keep_my_car/photo/photo_processor.dart';

import 'photo_test_support.dart';

void main() {
  late Directory root;
  late IoPhotoFileStorage storage;
  late FakeProcessor processor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('kmc-photo-storage-');
    storage = IoPhotoFileStorage(directory: () async => root);
    processor = FakeProcessor();
  });
  tearDown(() async {
    expect(root.absolute.path, startsWith(Directory.systemTemp.absolute.path));
    await root.delete(recursive: true);
  });
  File photo(String id) => File('${root.path}/photos/$id.jpg');

  test('UUID v4 generation and write/flush/revalidation/read', () async {
    final library = PhotoLibrary(storage: storage, processor: processor);
    final id = library.newId();
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    await library.prepare(id, 'source', PhotoCancellation());
    expect(await library.read(id), smallJpeg());
    expect(processor.validations, 4);
    expect(await File('${root.path}/photos/$id.photo-tmp').exists(), false);
  });

  test('final collision never overwrites existing image', () async {
    await storage.writeNew(photoA, smallJpeg(), processor);
    final before = await photo(photoA).readAsBytes();
    await expectLater(
      storage.writeNew(photoA, smallJpeg(), processor),
      throwsA(isA<FileSystemException>()),
    );
    expect(await photo(photoA).readAsBytes(), before);
  });

  test('tmp collision never overwrites the existing file', () async {
    await Directory('${root.path}/photos').create();
    final temp = File('${root.path}/photos/$photoA.photo-tmp');
    await temp.writeAsString('existing');
    await expectLater(
      storage.writeNew(photoA, smallJpeg(), processor),
      throwsA(isA<FileSystemException>()),
    );
    expect(await temp.readAsString(), 'existing');
    expect(await photo(photoA).exists(), false);
  });

  test('unsafe IDs rejected before file creation', () async {
    for (final id in [
      '../outside',
      '/tmp/image',
      '$photoA.jpg',
      photoA.toUpperCase(),
    ]) {
      await expectLater(
        storage.writeNew(id, smallJpeg(), processor),
        throwsA(isA<FormatException>()),
      );
    }
    expect(await Directory('${root.path}/photos').exists(), false);
  });

  test(
    'write failure and failed temp verification do not produce usable photo',
    () async {
      processor.onValidate = (_, count) {
        if (count == 2) throw const PhotoFailure(PhotoIssue.invalidImage);
      };
      await expectLater(
        storage.writeNew(photoA, smallJpeg(), processor),
        throwsA(isA<PhotoFailure>()),
      );
      expect(await photo(photoA).exists(), false);
      await File('${root.path}/photos/$photoA.photo-tmp').delete();
      await photo(photoA)
          .create(); // exclusive destination collision is a write failure
      processor.onValidate = null;
      await expectLater(
        storage.writeNew(photoA, smallJpeg(), processor),
        throwsA(isA<FileSystemException>()),
      );
      expect(await photo(photoA).length(), 0);
    },
  );

  test('actual final bytes are revalidated after promotion', () async {
    processor.onValidate = (_, count) async {
      if (count == 2) {
        await File('${root.path}/photos/$photoA.photo-tmp')
            .writeAsString('tampered');
      }
    };
    await expectLater(
      storage.writeNew(photoA, smallJpeg(), processor),
      throwsA(isA<PhotoFailure>()),
    );
    final library = PhotoLibrary(storage: storage, processor: FakeProcessor());
    expect(await library.read(photoA), null);
  });

  test(
    'cleanup retains both refs, unknown files and removes known orphan/tmp',
    () async {
      for (final id in [photoA, photoB, photoC]) {
        await storage.writeNew(id, smallJpeg(), processor);
      }
      final unknown = File('${root.path}/photos/keep-me.txt');
      await unknown.writeAsString('unknown');
      final stale = File('${root.path}/photos/$photoD.photo-tmp');
      await stale.writeAsString('stale');
      await storage.cleanup({photoA, photoB});
      expect(await photo(photoA).exists(), true);
      expect(await photo(photoB).exists(), true);
      expect(await photo(photoC).exists(), false);
      expect(await stale.exists(), false);
      expect(await unknown.readAsString(), 'unknown');
    },
  );

  for (final kind in ['directory', 'file']) {
    test('symlink $kind is not followed, overwritten or cleaned', () async {
      final outside = Directory('${root.path}/outside');
      await outside.create();
      final original = File('${outside.path}/original.jpg');
      await original.writeAsString('outside');
      final link = kind == 'directory'
          ? Link('${root.path}/photos')
          : Link('${root.path}/photos/$photoA.jpg');
      if (kind == 'file') await Directory('${root.path}/photos').create();
      try {
        await link.create(kind == 'directory' ? outside.path : original.path);
      } on FileSystemException {
        markTestSkipped('OS does not permit symlink creation');
        return;
      }
      if (kind == 'directory') {
        await expectLater(
          storage.writeNew(photoB, smallJpeg(), processor),
          throwsA(isA<PhotoFailure>()),
        );
        await expectLater(storage.cleanup({}), throwsA(isA<PhotoFailure>()));
      } else {
        await expectLater(storage.read(photoA), throwsA(isA<PhotoFailure>()));
        await expectLater(
          storage.writeNew(photoA, smallJpeg(), processor),
          throwsA(isA<FileSystemException>()),
        );
        await storage.cleanup({});
      }
      expect(await original.readAsString(), 'outside');
      expect(await link.exists(), true);
      await link.delete();
    });
  }

  test(
    'trusted root permits OS-style ancestor aliases but rejects root link',
    () async {
      final actual = Directory('${root.path}/real/base');
      await actual.create(recursive: true);
      final alias = Link('${root.path}/alias');
      try {
        await alias.create('${root.path}/real');
      } on FileSystemException {
        markTestSkipped('OS does not permit symlink creation');
        return;
      }
      try {
        final aliased = IoPhotoFileStorage(
          directory: () async => Directory('${alias.path}/base'),
        );
        await aliased.writeNew(photoA, smallJpeg(), processor);
        expect(await File('${actual.path}/photos/$photoA.jpg').exists(), true);
        final unsafe = IoPhotoFileStorage(
          directory: () async => Directory(alias.path),
        );
        await expectLater(
          unsafe.writeNew(photoB, smallJpeg(), processor),
          throwsA(isA<PhotoFailure>()),
        );
      } finally {
        await alias.delete();
      }
    },
  );

  test('missing/corrupt photos are absent to consumers', () async {
    final library = PhotoLibrary(storage: storage, processor: processor);
    expect(await library.read(photoA), null);
    await Directory('${root.path}/photos').create();
    await photo(photoA).writeAsBytes(Uint8List.fromList([1, 2, 3]));
    expect(await library.read(photoA), null);
  });

  test('valid marker structure with invalid JPEG data is absent after decoder failure', () async {
    await Directory('${root.path}/photos').create();
    await photo(photoA).writeAsBytes(corruptJpegScan());
    final library = PhotoLibrary(storage: storage, processor: processor);
    expect(await library.read(photoA), null);
    await photo(photoA).writeAsBytes(smallJpeg());
    expect(await library.read(photoA), smallJpeg());
  });

  test('read waits for cleanup and returns the protected image rather than absence', () async {
    final memory = MemoryPhotos()..files[photoA] = smallJpeg();
    final library = PhotoLibrary(storage: memory, processor: processor);
    final entered = Completer<void>();
    final release = Completer<void>();
    memory.onCleanup = () async {
      entered.complete();
      await release.future;
    };
    final cleaning = library.cleanup({photoA});
    await entered.future;
    final reading = library.read(photoA);
    expect(processor.validations, 0);
    release.complete();
    await cleaning;
    expect(await reading, smallJpeg());
  });

  test('read does not hide unrelated programming errors', () async {
    final memory = MemoryPhotos()..files[photoA] = smallJpeg();
    processor.onValidate = (_, _) => throw StateError('programming error');
    final library = PhotoLibrary(storage: memory, processor: processor);
    await expectLater(library.read(photoA), throwsA(isA<StateError>()));
  });
}
