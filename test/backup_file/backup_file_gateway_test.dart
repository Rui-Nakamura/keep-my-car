import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/backup_file/backup_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('keep_my_car/backup_file');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BackupFileGateway gateway;
  setUp(() => gateway = BackupFileGateway());
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('save passes filename MIME and exact bytes', () async {
    final bytes = Uint8List.fromList([0, 127, 255]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'save');
      expect(call.arguments['filename'], 'probe.kmcbackup');
      expect(call.arguments['mimeType'], 'application/octet-stream');
      expect(call.arguments['bytes'], bytes);
      return {'status': 'success'};
    });
    expect(
      (await gateway.save(
        filename: 'probe.kmcbackup',
        mimeType: 'application/octet-stream',
        bytes: bytes,
      )).status,
      BackupFileStatus.success,
    );
  });

  test('read returns exact bytes without metadata', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      expect(call.arguments, isNull);
      return {
        'status': 'success',
        'bytes': Uint8List.fromList([0, 255]),
      };
    });
    expect((await gateway.read()).bytes, [0, 255]);
  });

  for (final method in ['save', 'read']) {
    test('$method cancelled stays distinct', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'cancelled'},
      );
      final result = method == 'read'
          ? await gateway.read()
          : await gateway.save(
              filename: 'x',
              mimeType: 'text/plain',
              bytes: Uint8List(0),
            );
      expect(result.status, BackupFileStatus.cancelled);
      expect(result.error, isNull);
      expect(result.bytes, isNull);
    });
  }

  for (final error in BackupFileError.values) {
    test('fixed error ${error.name} never becomes success', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'status': 'error', 'code': error.name},
      );
      final result = await gateway.read();
      expect(result.status, BackupFileStatus.error);
      expect(result.error, error);
      expect(result.bytes, isNull);
    });
  }

  final malformed = <Object?>[
    null,
    'success',
    {},
    {'status': 'unknown'},
    {'status': 'success'},
    {
      'status': 'success',
      'bytes': [1, 2],
    },
    {'status': 'success', 'bytes': Uint8List(0), 'code': 'ioFailure'},
    {'status': 'cancelled', 'bytes': Uint8List(0)},
    {'status': 'error', 'code': 'provider secret'},
    {'status': 'error', 'code': 'ioFailure', 'bytes': Uint8List(0)},
  ];
  for (var i = 0; i < malformed.length; i++) {
    test('malformed response $i is rejected', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => malformed[i]);
      expect((await gateway.read()).error, BackupFileError.invalidResponse);
    });
  }

  test('platform exception text is not returned', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'secret',
        message: 'private provider details',
      ),
    );
    expect((await gateway.read()).error, BackupFileError.platformFailure);
  });

  test('missing native channel fails safely', () async {
    expect((await gateway.read()).error, BackupFileError.platformFailure);
  });

  test('OS selection has no Dart deadline', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final operation = gateway.read();
    pending.complete({'status': 'cancelled'});
    expect((await operation).status, BackupFileStatus.cancelled);
  });
}
