import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum DataFile {
  current('keep_my_car.json'),
  temp('keep_my_car.tmp'),
  backup('keep_my_car.backup.json');

  const DataFile(this.fileName);
  final String fileName;
}

/// Narrow file boundary, injectable for deterministic I/O failure tests.
abstract interface class LocalFileStorage {
  Future<void> prepare();
  Future<List<int>?> read(DataFile file);
  Future<void> writeTemp(List<int> bytes);
  Future<void> move(DataFile source, DataFile destination);
  Future<void> delete(DataFile file);
}

/// All three files live in one directory on the same filesystem.
/// Application code should own one repository for this storage directory.
class IoLocalFileStorage implements LocalFileStorage {
  IoLocalFileStorage({required Future<Directory> Function() directory})
    : _directoryProvider = directory;

  factory IoLocalFileStorage.applicationSupport() =>
      IoLocalFileStorage(directory: getApplicationSupportDirectory);

  final Future<Directory> Function() _directoryProvider;
  Directory? _resolvedDirectory;

  Future<Directory> _directory() async =>
      _resolvedDirectory ??= await _directoryProvider();

  Future<File> _file(DataFile file) async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}${file.fileName}');
  }

  @override
  Future<void> prepare() async => (await _directory()).create(recursive: true);

  @override
  Future<List<int>?> read(DataFile file) async {
    final target = await _file(file);
    try {
      return await target.readAsBytes();
    } on FileSystemException catch (error) {
      // A missing file/directory is different from permission or device errors.
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) return null;
      rethrow;
    }
  }

  @override
  Future<void> writeTemp(List<int> bytes) async {
    await (await _file(DataFile.temp)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> move(DataFile source, DataFile destination) async {
    await (await _file(source)).rename((await _file(destination)).path);
  }

  @override
  Future<void> delete(DataFile file) async {
    final target = await _file(file);
    if (await target.exists()) await target.delete();
  }
}
