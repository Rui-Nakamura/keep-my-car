import 'dart:typed_data';

import '../persistence/keep_my_car_data_mapper.dart';

enum ZipBackupIssue {
  invalidZip,
  unsupportedZip,
  sizeLimit,
  invalidManifest,
  integrity,
  invalidPlan,
  invalidPhoto,
  unsupportedVersion,
}

/// Also used by encode, whose invalid caller input cannot produce a ZIP.
final class ZipBackupFailure implements Exception, ZipBackupDecodeResult {
  const ZipBackupFailure(this.issue);
  final ZipBackupIssue issue;
  @override
  String toString() => 'ZipBackupFailure(${issue.name})';
}

sealed class ZipBackupDecodeResult {
  const ZipBackupDecodeResult();
}

/// Fully validated in-memory candidate, NOT an applied import.
final class ZipBackupSuccess extends ZipBackupDecodeResult {
  ZipBackupSuccess(this.plan, Uint8List? jpeg)
    : jpeg = jpeg == null
          ? null
          : Uint8List.fromList(jpeg).asUnmodifiableView();

  final RestoredCarData plan;
  // Private copy: never a view into caller-owned input.
  final Uint8List? jpeg;
}
