import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../persistence/keep_my_car_data_mapper.dart';
import 'zip_backup_codec.dart';
import 'zip_backup_result.dart';

/// Memory-only work. The static tail also serializes separate worker instances;
/// cancellation in the transfer ignores a result, it does not kill this worker.
class ZipBackupWorker {
  static Future<void> _tail = Future.value();

  static Future<T> _run<T>(Future<T> Function() work) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
    }
  }

  Future<Uint8List> encode(RestoredCarData plan, {Uint8List? jpeg}) =>
      _run(() => _encode(plan, jpeg));

  Future<ZipBackupDecodeResult> decode(Uint8List bytes) =>
      _run(() => _decode(bytes));
}

// These closures capture only value arguments, never a service or UI owner.
Future<Uint8List> _encode(RestoredCarData plan, Uint8List? jpeg) =>
    Isolate.run(() => const ZipBackupCodec().encode(plan, jpeg: jpeg));

Future<ZipBackupDecodeResult> _decode(Uint8List bytes) =>
    Isolate.run(() => const ZipBackupCodec().decode(bytes));
