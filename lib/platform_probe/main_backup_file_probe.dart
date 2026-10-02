import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'backup_file_gateway.dart';

void main() {
  if (!kDebugMode) throw StateError('This entrypoint is debug-only.');
  runApp(const MaterialApp(home: BackupFileProbe()));
}

class BackupFileProbe extends StatefulWidget {
  const BackupFileProbe({super.key});

  @override
  State<BackupFileProbe> createState() => _BackupFileProbeState();
}

class _BackupFileProbeState extends State<BackupFileProbe> {
  final _gateway = BackupFileGateway();
  final _bytes = Uint8List.fromList(
    utf8.encode('Keep My Car Step 14-C2 probe\n日本語\n1234567890\n'),
  );
  bool _waiting = false;
  String _message = '保存・読込み・それぞれのCancelを検証します。';

  Future<void> _run(bool saving) async {
    setState(() {
      _waiting = true;
      _message = 'OS画面で選択してください。I/O開始後の制限は60秒です。';
    });
    final result = saving
        ? await _gateway.save(
            filename: 'KeepMyCar_Backup_Probe.kmcbackup',
            mimeType: 'application/octet-stream',
            bytes: _bytes,
          )
        : await _gateway.read();
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _message = switch (result.status) {
        BackupFileStatus.success =>
          saving
              ? 'success：write・flush・close完了'
              : 'success：${result.bytes!.length} bytes、固定bytes一致：'
                    '${listEquals(result.bytes, _bytes)}',
        BackupFileStatus.cancelled => 'cancelled',
        BackupFileStatus.error => 'error：${result.error!.name}',
      };
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Step 14-C2 検証専用')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('実データ・復元処理には接続していません。'),
        const Text('保存失敗時も空／部分ファイルが残る可能性があります。'),
        FilledButton(
          onPressed: _waiting ? null : () => _run(true),
          child: const Text('固定bytesを保存'),
        ),
        FilledButton(
          onPressed: _waiting ? null : () => _run(false),
          child: const Text('1ファイルを読込み'),
        ),
        Text(_message),
      ],
    ),
  );
}
