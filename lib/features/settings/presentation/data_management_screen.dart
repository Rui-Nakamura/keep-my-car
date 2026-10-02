import 'package:flutter/material.dart';

import '../../../app/save_progress.dart';
import '../../../app/theme/app_spacing.dart';

/// Presentation only: file transport, validation and persistence stay outside.
class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({
    super.key,
    required this.onRestore,
    this.onExport,
    this.onStartNew,
    this.failure = false,
    this.onReload,
  });

  final Future<void> Function(BuildContext) onRestore;
  final Future<void> Function(BuildContext)? onExport;
  final Future<void> Function(BuildContext)? onStartNew;
  final Future<void> Function()? onReload;
  final bool failure;

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool busy = false;

  Future<void> run(Future<void> Function(BuildContext) action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SaveProgress(
    saving: busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.onExport == null ? 'Keep My Car' : 'データ管理'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.failure) ...[
                Text(
                  '保存データを読み込めませんでした',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'バックアップがある場合は、バックアップから復元できます。\nバックアップがない場合は、新しく設定して使い始めることもできます。',
                ),
              ],
              if (widget.onStartNew != null && !widget.failure) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: busy ? null : () => run(widget.onStartNew!),
                  child: const Text('新しく設定する'),
                ),
              ],
              if (widget.onExport != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: busy ? null : () => run(widget.onExport!),
                  child: const Text('データを書き出す'),
                ),
                const Text('現在のデータをバックアップファイルとして保存します'),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (widget.failure)
                FilledButton(
                  onPressed: busy ? null : () => run(widget.onRestore),
                  child: const Text('バックアップから復元する'),
                )
              else
                OutlinedButton(
                  onPressed: busy ? null : () => run(widget.onRestore),
                  child: const Text('バックアップから復元する'),
                ),
              const Text('保存してあるバックアップからデータを復元します'),
              if (widget.failure && widget.onStartNew != null) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: busy ? null : () => run(widget.onStartNew!),
                  child: const Text('新しく設定する'),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'バックアップファイルには、車両情報や計画金額など入力した情報が含まれます。第三者へ共有しないようご注意ください。',
              ),
              if (widget.onReload != null) ...[
                const SizedBox(height: AppSpacing.xl),
                TextButton(
                  onPressed: busy ? null : () => run((_) => widget.onReload!()),
                  child: const Text('もう一度読み込む'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
