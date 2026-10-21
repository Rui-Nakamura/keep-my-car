import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../persistence/keep_my_car_data_mapper.dart';
import '../photo/photo_processor.dart';
import 'src/strict_backup_json.dart';
import 'src/zip_backup_structure.dart';
import 'src/zip_plan_schema_v1.dart';
import 'zip_backup_result.dart';

/// Fixed-profile ZIP Backup v1. Memory only: no import application or file I/O.
/// Public async boundary; no candidate is exposed before ALL checks pass.
class ZipBackupCodec {
  const ZipBackupCodec();
  static const _plan = ZipPlanSchemaV1();
  static const _format = 'keep-my-car-zip-backup';

  /// Invalid input throws ZipBackupFailure; no partial ZIP is returned.
  Future<Uint8List> encode(RestoredCarData plan, {Uint8List? jpeg}) async {
    final Uint8List planBytes;
    try {
      planBytes = _plan.encode(plan);
    } on FormatException {
      throw const ZipBackupFailure(ZipBackupIssue.invalidPlan);
    } on ArgumentError {
      throw const ZipBackupFailure(ZipBackupIssue.invalidPlan);
    }
    _limit('plan.json', planBytes.length);
    if (jpeg != null) {
      _limit('photo.jpg', jpeg.length);
      _photo(jpeg);
    }
    final files = <String, Uint8List>{
      'plan.json': planBytes,
      'photo.jpg': ?jpeg,
    };
    final manifest = utf8.encode(
      jsonEncode({
        'format': _format,
        'formatVersion': 1,
        'planSchemaVersion': 1,
        'hasPhoto': jpeg != null,
        'files': {
          for (final file in files.entries)
            file.key: {
              'sizeBytes': file.value.length,
              'sha256': sha256.convert(file.value).toString(),
            },
        },
      }),
    );
    _limit('manifest.json', manifest.length);
    final archive = Archive();
    for (final file in {'manifest.json': manifest, ...files}.entries) {
      archive.addFile(
        ArchiveFile.bytes(file.key, file.value)
          ..compression = CompressionType.none,
      );
    }
    final bytes = ZipEncoder().encodeBytes(archive);
    inspectBackupZip(bytes); // Includes the final ZIP-wide size check.
    return bytes;
  }

  Future<ZipBackupDecodeResult> decode(Uint8List bytes) async {
    try {
      final entries = inspectBackupZip(bytes);
      // All structural and declared-size validation precedes any expansion.
      final files = <String, Uint8List>{};
      var remaining = ZipBackupLimits.expanded;
      for (final entry in entries) {
        final maximum = math.min(
          remaining,
          math.min(entry.size, ZipBackupLimits.files[entry.name]!),
        );
        final output = BackupBoundedOutput(maximum);
        try {
          final compressed = Uint8List.sublistView(
            bytes,
            entry.dataOffset,
            entry.dataOffset + entry.compressedSize,
          );
          if (entry.method == 0) {
            output.writeBytes(compressed);
          } else {
            // archive 4.5.2 native: NativeChunkDecoder -> OutputStream.writeBytes.
            // Our typed bounded output checks each chunk BEFORE forwarding it.
            // B案: this API does not prove Deflate termination/input consumption.
            final ok = const ZLibDecoder().decodeStream(
              InputMemoryStream(compressed),
              output,
              raw: true,
            );
            if (!ok) throw const ZipBackupFailure(ZipBackupIssue.integrity);
          }
          final expanded = output.getBytes();
          if (expanded.length != entry.size ||
              getCrc32(expanded) != entry.crc) {
            throw const ZipBackupFailure(ZipBackupIssue.integrity);
          }
          remaining -= expanded.length;
          files[entry.name] = expanded;
        } on ArchiveException {
          throw const ZipBackupFailure(ZipBackupIssue.integrity);
        } on FormatException {
          throw const ZipBackupFailure(ZipBackupIssue.integrity);
        } finally {
          output.closeSync();
        }
      }
      _manifest(files);
      final RestoredCarData plan;
      try {
        plan = _plan.decode(files['plan.json']!);
      } on FormatException {
        throw const ZipBackupFailure(ZipBackupIssue.invalidPlan);
      } on ArgumentError {
        throw const ZipBackupFailure(ZipBackupIssue.invalidPlan);
      }
      final photo = files['photo.jpg'];
      if (photo != null) _photo(photo);
      return ZipBackupSuccess(plan, photo);
    } on ZipBackupFailure catch (failure) {
      return failure;
    }
  }

  void _limit(String name, int length) {
    if (length > ZipBackupLimits.files[name]!) {
      throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
    }
  }

  void _photo(Uint8List bytes) {
    try {
      validatePhotoJpeg(bytes);
    } on PhotoFailure {
      throw const ZipBackupFailure(ZipBackupIssue.invalidPhoto);
    }
  }

  void _manifest(Map<String, Uint8List> files) {
    try {
      final root = exactBackupObject(
        strictBackupJson(files['manifest.json']!),
        {'format', 'formatVersion', 'planSchemaVersion', 'hasPhoto', 'files'},
      );
      if (root['format'] != _format || root['hasPhoto'] is! bool) {
        throw const FormatException('Invalid manifest identity');
      }
      for (final key in ['formatVersion', 'planSchemaVersion']) {
        final version = root[key];
        if (version is! int || version < 1) {
          throw const FormatException('Invalid manifest version');
        }
        if (version != 1) {
          throw const ZipBackupFailure(ZipBackupIssue.unsupportedVersion);
        }
      }
      final hasPhoto = root['hasPhoto'] as bool;
      if (hasPhoto != files.containsKey('photo.jpg')) {
        throw const FormatException('Photo presence mismatch');
      }
      final declarations = exactBackupObject(root['files'], {
        'plan.json',
        if (hasPhoto) 'photo.jpg',
      });
      for (final entry in declarations.entries) {
        final declaration = exactBackupObject(entry.value, {
          'sizeBytes',
          'sha256',
        });
        final size = declaration['sizeBytes'];
        final hash = declaration['sha256'];
        if (size is! int ||
            size < 0 ||
            hash is! String ||
            hash.length != 64 ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw const FormatException('Invalid file declaration');
        }
        final content = files[entry.key]!;
        if (size != content.length ||
            sha256.convert(content).toString() != hash) {
          throw const ZipBackupFailure(ZipBackupIssue.integrity);
        }
      }
    } on FormatException {
      throw const ZipBackupFailure(ZipBackupIssue.invalidManifest);
    }
  }
}
