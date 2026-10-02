import 'dart:convert';
import 'dart:typed_data';

import '../persistence/keep_my_car_data_dto.dart';
import '../persistence/keep_my_car_data_mapper.dart';
import '../persistence/keep_my_car_payload_codec.dart';
import 'backup_import_result.dart';

/// OS-independent UTF-8 backup v1. No file access, clock, or state mutation.
class BackupV1Codec {
  const BackupV1Codec();

  static const _format = 'keep-my-car-backup';
  static const _version = 1;
  static const _mapper = KeepMyCarDataMapper();
  static const _payload = KeepMyCarPayloadCodec();

  /// Mapper validates domain invariants and storage grammar before encoding.
  /// Invalid caller data throws the mapper's ArgumentError/FormatException.
  Uint8List encode(RestoredCarData data, {required DateTime createdAt}) {
    final dto = _mapper.toDto(
      ownerBirthMonth: data.ownerBirthMonth,
      car: data.car,
      planConditions: data.planConditions,
      plannedExpenses: data.plannedExpenses,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': _format,
          'exportFormatVersion': _version,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'data': _payload.encode(dto),
        }),
      ),
    );
  }

  /// Unknown fields are ignored. No partial candidate escapes validation.
  BackupImportResult decode(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return const BackupImportFailure(BackupImportIssue.invalidStructure);
    }
    if (decoded is! Map<String, dynamic>) {
      return const BackupImportFailure(BackupImportIssue.invalidStructure);
    }
    if (decoded['format'] != _format) {
      return const BackupImportFailure(BackupImportIssue.notBackup);
    }
    final version = decoded['exportFormatVersion'];
    if (version is! int) {
      return const BackupImportFailure(BackupImportIssue.invalidStructure);
    }
    if (version != _version) {
      return const BackupImportFailure(BackupImportIssue.unsupportedVersion);
    }
    final createdAt = decoded['createdAt'];
    final payload = decoded['data'];
    if (createdAt is! String ||
        !_validCreatedAt(createdAt) ||
        payload is! Map<String, dynamic>) {
      return const BackupImportFailure(BackupImportIssue.invalidStructure);
    }

    final KeepMyCarDataDto dto;
    try {
      dto = _payload.decode(payload);
    } on FormatException {
      return const BackupImportFailure(BackupImportIssue.invalidStructure);
    }
    try {
      // Includes validateStorageFormat, domain invariants, IDs and mileage
      // consistency. Time-dependent editor rules intentionally do not apply.
      return BackupImportSuccess(_mapper.toDomain(dto));
    } on FormatException {
      return const BackupImportFailure(BackupImportIssue.invalidContent);
    } on ArgumentError {
      return const BackupImportFailure(BackupImportIssue.invalidContent);
    }
  }

  // Match the calendar-date forms understood by Dart, then reject component
  // overflow rather than silently accepting DateTime.parse's normalization.
  // Validate the written date before timezone conversion changes the day.
  static final _timestamp = RegExp(
    r'^([+-]?[0-9]{4,6})(-?)([0-9]{2})\2([0-9]{2})'
    r'(?:[ T]([0-9]{2})(?:(:?)([0-9]{2})(?:\6([0-9]{2})(?:[.,]([0-9]+))?)?)?'
    r'(?:[zZ]|[-+]([0-9]{2})(?::?([0-9]{2}))?)?)?$',
  );

  bool _validCreatedAt(String value) {
    final match = _timestamp.firstMatch(value);
    if (match == null ||
        match.end != value.length ||
        DateTime.tryParse(value) == null) {
      return false;
    }
    int part(int group) => int.parse(match.group(group) ?? '0');
    final year = part(1);
    final month = part(3);
    final day = part(4);
    if (month < 1 || month > 12 || day < 1) return false;
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (day > days[month - 1]) return false;
    final hour = part(5);
    if (hour > 24 ||
        part(7) > 59 ||
        part(8) > 59 ||
        part(10) > 23 ||
        part(11) > 59) {
      return false;
    }
    // ISO end-of-day notation is valid only at exactly 24:00:00.
    return hour != 24 ||
        (part(7) == 0 &&
            part(8) == 0 &&
            !(match.group(9) ?? '').contains(RegExp('[1-9]')));
  }
}
