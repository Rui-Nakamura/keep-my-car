import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../persistence/storage_format.dart';
import 'photo_processor.dart';

abstract interface class PhotoFileStorage {
  Future<void> writeNew(String id, Uint8List jpeg, PhotoProcessor validator);
  Future<Uint8List?> read(String id);
  Future<void> cleanup(Set<String> protectedIds);
}

/// Single app owner, app-private directory. Checks links/canonical paths before
/// access. This does not claim protection against another process concurrently
/// replacing filesystem entries, or atomicity with the separate JSON transaction.
class IoPhotoFileStorage implements PhotoFileStorage {
  IoPhotoFileStorage({required this.directory});
  factory IoPhotoFileStorage.applicationSupport() =>
      IoPhotoFileStorage(directory: getApplicationSupportDirectory);
  final Future<Directory> Function() directory;

  Future<Directory?> _photos({bool create = false}) async {
    final provided = (await directory()).absolute;
    final rootType = await FileSystemEntity.type(
      provided.path,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory &&
        rootType != FileSystemEntityType.notFound) {
      throw const PhotoFailure(PhotoIssue.unsafePath);
    }
    if (rootType == FileSystemEntityType.notFound) {
      if (!create) return null;
      await provided.create(recursive: true);
    }
    // The directory provider is trusted configuration (Application Support),
    // never user input. OS ancestors may legitimately be aliases, e.g. iOS /var.
    // Anchor once to that resolved root; reject all links in our photos subtree.
    final root = Directory(await provided.resolveSymbolicLinks());
    final photos = Directory('${root.path}${Platform.pathSeparator}photos');
    final type = await FileSystemEntity.type(photos.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && !create) return null;
    if (type == FileSystemEntityType.notFound) await photos.create();
    if (await FileSystemEntity.type(photos.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const PhotoFailure(PhotoIssue.unsafePath);
    }
    await _canonical(photos.path);
    return photos;
  }

  Future<void> _canonical(String path) async {
    var expected = File(path).absolute.uri.normalizePath().toFilePath();
    var actual = await File(path).resolveSymbolicLinks();
    if (Platform.isWindows) {
      expected = expected.toLowerCase();
      actual = actual.toLowerCase();
    }
    if (expected != actual) throw const PhotoFailure(PhotoIssue.unsafePath);
  }

  Future<void> _regular(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const PhotoFailure(PhotoIssue.unsafePath);
    }
    await _canonical(file.path);
  }

  @override
  Future<void> writeNew(
    String id,
    Uint8List jpeg,
    PhotoProcessor validator,
  ) async {
    validatePhotoId(id);
    await validator.validate(jpeg);
    final directory = (await _photos(create: true))!;
    final temp = File(
      '${directory.path}${Platform.pathSeparator}$id.photo-tmp',
    );
    final target = File('${directory.path}${Platform.pathSeparator}$id.jpg');
    // Both names are exclusively created. Never overwrite a pre-existing photo,
    // tmp, link or directory, even when the UUID source is faulty.
    await temp.create(exclusive: true);
    await _regular(temp);
    await temp.writeAsBytes(jpeg, flush: true);
    await _regular(temp);
    final written = await _boundedRead(temp);
    await validator.validate(written);
    if (!_equal(written, jpeg)) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
    await target.create(exclusive: true);
    // Reserve the destination before rename (Dart rename otherwise replaces it).
    // Only our own empty reservation may be replaced. A crash leaves a harmless
    // unreferenced empty file, which read validation rejects.
    await _regular(target);
    if (await target.length() != 0) {
      throw const PhotoFailure(PhotoIssue.unsafePath);
    }
    await temp.rename(target.path);
    await _regular(target);
    final committed = await _boundedRead(target);
    await validator.validate(committed);
    if (!_equal(committed, jpeg)) {
      throw const PhotoFailure(PhotoIssue.invalidImage);
    }
  }

  @override
  Future<Uint8List?> read(String id) async {
    validatePhotoId(id);
    final directory = await _photos();
    if (directory == null) return null;
    final file = File('${directory.path}${Platform.pathSeparator}$id.jpg');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _regular(file);
    return _boundedRead(file);
  }

  Future<Uint8List> _boundedRead(File file) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length > DartPhotoProcessor.maxOutputBytes) {
        throw const PhotoFailure(PhotoIssue.outputLimit);
      }
      final bytes = await handle.read(length);
      if (bytes.length != length || await handle.length() != length) {
        throw const PhotoFailure(PhotoIssue.invalidImage);
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> cleanup(Set<String> protectedIds) async {
    for (final id in protectedIds) {
      validatePhotoId(id);
    }
    final directory = await _photos();
    if (directory == null) return;
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      final suffix = name.endsWith('.photo-tmp') ? '.photo-tmp' : '.jpg';
      if (!name.endsWith(suffix)) continue;
      final id = name.substring(0, name.length - suffix.length);
      try {
        validatePhotoId(id);
      } on FormatException {
        continue;
      }
      if (protectedIds.contains(id)) continue;
      // Never follow or remove unknown entries, links, or subdirectories.
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      await _canonical(directory.path);
      final file = File(entry.path);
      await _regular(file);
      await file.delete();
    }
  }

  bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
