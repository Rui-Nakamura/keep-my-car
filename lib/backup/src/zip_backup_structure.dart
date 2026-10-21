import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../zip_backup_result.dart';

abstract final class ZipBackupLimits {
  static const zip = 12 * 1024 * 1024;
  static const expanded = 16 * 1024 * 1024;
  static const files = {
    'manifest.json': 32 * 1024,
    'plan.json': 5 * 1024 * 1024,
    'photo.jpg': 3 * 1024 * 1024,
  };
}

class ZipBackupEntry {
  const ZipBackupEntry(
    this.name,
    this.method,
    this.crc,
    this.size,
    this.compressedSize,
    this.dataOffset,
    this.localOffset,
    this.end,
  );
  final String name;
  final int method, crc, size, compressedSize, dataOffset, localOffset, end;
}

Never _invalid() => throw const ZipBackupFailure(ZipBackupIssue.invalidZip);
Never _unsupported() =>
    throw const ZipBackupFailure(ZipBackupIssue.unsupportedZip);

/// A fixed 2-3 entry profile guard. Never decompresses or normalizes paths.
List<ZipBackupEntry> inspectBackupZip(Uint8List bytes) {
  if (bytes.length > ZipBackupLimits.zip) {
    throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
  }
  final data = ByteData.sublistView(bytes);
  void range(int start, int count, [int? boundary]) {
    if (start < 0 || count < 0 || start + count > (boundary ?? bytes.length)) {
      _invalid();
    }
  }

  int u16(int p) {
    range(p, 2);
    return data.getUint16(p, Endian.little);
  }

  int u32(int p) {
    range(p, 4);
    return data.getUint32(p, Endian.little);
  }

  List<ZipBackupEntry> inspectAt(int eocd) {
    final count = u16(eocd + 10);
    final directorySize = u32(eocd + 12);
    final directory = u32(eocd + 16);
    if (count == 0xffff ||
        directorySize == 0xffffffff ||
        directory == 0xffffffff) {
      _unsupported();
    }
    if (u16(eocd + 4) != 0 || u16(eocd + 6) != 0) _unsupported();
    if (u16(eocd + 8) != count || count < 2 || count > 3) _invalid();
    range(directory, directorySize, eocd);
    if (directory + directorySize != eocd) _invalid();

    final entries = <ZipBackupEntry>[];
    final names = <String>{};
    var total = 0;
    var p = directory;
    for (var i = 0; i < count; i++) {
      range(p, 46, eocd);
      if (u32(p) != 0x02014b50) _invalid();
      final version = u16(p + 6);
      final flags = u16(p + 8);
      final method = u16(p + 10);
      final crc = u32(p + 16);
      final compressed = u32(p + 20);
      final size = u32(p + 24);
      final nameLength = u16(p + 28);
      final extraLength = u16(p + 30);
      final commentLength = u16(p + 32);
      final local = u32(p + 42);
      if (compressed == 0xffffffff ||
          size == 0xffffffff ||
          local == 0xffffffff ||
          version > 20 ||
          u16(p + 34) != 0) {
        _unsupported();
      }
      if (version < 10 || (method == 8 && version < 20)) _unsupported();
      if (method != 0 && method != 8) _unsupported();
      // Encryption and every reserved/unsupported flag are excluded.
      final allowedFlags = 0x0808 | (method == 8 ? 0x0006 : 0);
      if ((flags & ~allowedFlags) != 0 || extraLength != 0) _unsupported();
      final attributes = u32(p + 38);
      final fileType = (attributes >>> 16) & 0xf000;
      if ((fileType != 0 && fileType != 0x8000) ||
          (attributes & 0x0000ffd8) != 0) {
        _unsupported();
      }
      range(p + 46, nameLength + extraLength + commentLength, eocd);
      if (nameLength != 9 && nameLength != 13) _invalid();
      final name = String.fromCharCodes(
        Uint8List.sublistView(bytes, p + 46, p + 46 + nameLength),
      );
      final limit = ZipBackupLimits.files[name];
      if (limit == null || !names.add(name)) _invalid();
      if (size > limit || compressed > ZipBackupLimits.zip) {
        throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
      }
      total += size;
      if (total > ZipBackupLimits.expanded) {
        throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
      }
      if (method == 0 && compressed != size) _invalid();
      range(local, 30, directory);
      if (u32(local) != 0x04034b50) _invalid();
      if (u16(local + 4) != version ||
          u16(local + 6) != flags ||
          u16(local + 8) != method ||
          u32(local + 10) != u32(p + 12) ||
          u16(local + 26) != nameLength) {
        _invalid();
      }
      if (u16(local + 28) != 0) _unsupported();
      range(local + 30, nameLength, directory);
      for (var n = 0; n < nameLength; n++) {
        if (bytes[local + 30 + n] != bytes[p + 46 + n]) _invalid();
      }
      final descriptor = (flags & 8) != 0;
      for (final (offset, expected) in [
        (14, crc),
        (18, compressed),
        (22, size),
      ]) {
        final value = u32(local + offset);
        if (value != expected && !(descriptor && value == 0)) _invalid();
      }
      final start = local + 30 + nameLength;
      range(start, compressed, directory);
      var end = start + compressed;
      if (descriptor) {
        range(end, 16, directory);
        if (u32(end) != 0x08074b50 ||
            u32(end + 4) != crc ||
            u32(end + 8) != compressed ||
            u32(end + 12) != size) {
          _invalid();
        }
        end += 16;
      }
      entries.add(
        ZipBackupEntry(name, method, crc, size, compressed, start, local, end),
      );
      p += 46 + nameLength + extraLength + commentLength;
    }
    if (p != eocd || !names.containsAll(['manifest.json', 'plan.json'])) {
      _invalid();
    }
    final ordered = [...entries]
      ..sort((a, b) => a.localOffset.compareTo(b.localOffset));
    var end = 0;
    for (final entry in ordered) {
      if (entry.localOffset != end) _invalid();
      end = entry.end;
    }
    if (end != directory) _invalid();
    return entries;
  }

  // A legal comment may itself contain EOCD-like bytes. Try candidates only
  // within the 16-bit comment window and require the complete fixed structure.
  ZipBackupFailure? lastFailure;
  final earliest = (bytes.length - 22 - 65535).clamp(0, bytes.length);
  for (var p = bytes.length - 22; p >= earliest; p--) {
    if (u32(p) == 0x06054b50 && p + 22 + u16(p + 20) == bytes.length) {
      try {
        return inspectAt(p);
      } on ZipBackupFailure catch (failure) {
        lastFailure = failure;
      }
    }
  }
  throw lastFailure ?? const ZipBackupFailure(ZipBackupIssue.invalidZip);
}

/// Checks BEFORE forwarding any write or allocating for it. Does not preallocate
/// the untrusted declared size. Covers Stored and native archive Deflate output.
/// Shared remaining budget is enforced by the caller for each sequential entry.
class BackupBoundedOutput extends OutputMemoryStream {
  BackupBoundedOutput(this.maximum) : super(size: 1024);
  final int maximum;
  void _check(int count) {
    if (count < 0 || length + count > maximum) {
      throw const ZipBackupFailure(ZipBackupIssue.sizeLimit);
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
