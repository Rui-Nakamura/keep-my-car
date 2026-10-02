import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../backup/backup_transfer.dart';
import '../backup/backup_import_result.dart';
import '../backup_file/backup_file_gateway.dart';
import '../features/settings/presentation/data_management_screen.dart';

import '../domain/models/year_month.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/initial_setup/presentation/initial_setup_screen.dart';
import '../persistence/keep_my_car_repository.dart';
import '../persistence/local_file_storage.dart';
import 'persistent_plan_state.dart';
import 'screen_success_feedback.dart';
import 'save_request.dart';
import 'theme/app_theme.dart';

class KeepMyCarApp extends StatefulWidget {
  const KeepMyCarApp({
    super.key,
    this.repository,
    this.now,
    this.sessionFactory,
    this.backupGateway,
  });
  final KeepMyCarRepository? repository;
  final DateTime Function()? now;
  final SessionFactory? sessionFactory;
  final BackupFileGateway? backupGateway;
  @override
  State<KeepMyCarApp> createState() => _KeepMyCarAppState();
}

class _KeepMyCarAppState extends State<KeepMyCarApp> {
  final navigator = GlobalKey<NavigatorState>();
  late final PersistentPlanState state;
  late final BackupTransfer transfer;
  bool settingUp = false;
  int successNotificationId = 0;
  StartupPhase previous = StartupPhase.loading;
  bool recoveryDialog = false;
  @override
  void initState() {
    super.initState();
    final now = (widget.now ?? DateTime.now)().toLocal();
    state = PersistentPlanState(
      repository:
          widget.repository ??
          KeepMyCarRepository(IoLocalFileStorage.applicationSupport()),
      referenceMonth: YearMonth(now.year, now.month),
      sessionFactory: widget.sessionFactory,
    )..addListener(changed);
    transfer = BackupTransfer(
      state: state,
      gateway: widget.backupGateway,
      now: widget.now,
    );
    state.load();
  }

  void changed() {
    if (!mounted) return;
    if (state.phase != previous &&
        (state.phase == StartupPhase.uncertain ||
            state.phase == StartupPhase.loading)) {
      navigator.currentState?.popUntil((route) => route.isFirst);
    }
    previous = state.phase;
    if (state.phase != StartupPhase.noData) settingUp = false;
    setState(() {});
    if (state.phase == StartupPhase.recovered && !recoveryDialog) {
      recoveryDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showDialog<void>(
          context: navigator.currentContext!,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('データを復元しました'),
            content: const Text('前回の保存データを読み込めなかったため、直前の正常なデータから復元しました。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) {
          recoveryDialog = false;
          state.acknowledgeRecovery();
        }
      });
    }
  }

  static const generalError = '処理を完了できませんでした。もう一度お試しください';

  void feedback(BuildContext context, String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String transferError(BackupTransferResult result) =>
      switch (result.importIssue) {
        BackupImportIssue.notBackup => 'このファイルはKeep My Carのバックアップではありません',
        BackupImportIssue.unsupportedVersion =>
          'このバックアップは新しいバージョンで作成されているため、このアプリでは読み込めません',
        BackupImportIssue.invalidStructure ||
        BackupImportIssue.invalidContent => 'バックアップファイルを読み込めませんでした',
        null =>
          result.fileError == BackupFileError.tooLarge
              ? 'バックアップファイルを読み込めませんでした'
              : generalError,
      };

  Future<bool> confirm(
    BuildContext context,
    String title,
    String body,
    String action, {
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            if (destructive)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
          ],
        ),
      ) ==
      true;

  Future<void> export(BuildContext context) async {
    try {
      final result = await transfer.export();
      if (!context.mounted) return;
      if (result.status == BackupTransferStatus.success) {
        feedback(context, 'データを書き出しました');
      }
      if (result.status == BackupTransferStatus.error) {
        feedback(context, transferError(result));
      }
    } catch (_) {
      feedback(context, generalError);
    }
  }

  Future<void> restore(BuildContext context) async {
    try {
      final read = await transfer.readCandidate();
      if (!context.mounted) return;
      if (read.status == BackupTransferStatus.cancelled) return;
      if (read.status != BackupTransferStatus.candidate) {
        feedback(context, transferError(read));
        return;
      }
      // Recheck the CURRENT phase after confirmation as well as after validation.
      // A candidate carries no assumptions about the target's startup phase.
      while (true) {
        if (!context.mounted) return;
        final phase = state.phase;
        if (!state.canRestoreBackup) {
          feedback(context, generalError);
          return;
        }
        if (phase != StartupPhase.noData) {
          final accepted = await confirm(
            context,
            'バックアップから復元しますか？',
            phase == StartupPhase.failure
                ? '現在読み込めない保存データは、選択したバックアップの内容に置き換わり、元に戻せません。'
                : '現在のデータは、選択したバックアップの内容に置き換わります。',
            'バックアップから復元する',
          );
          if (!context.mounted || !accepted) return;
        }
        if (state.phase != phase) continue;
        final result = await transfer.restore(read.candidate!);
        if (!mounted) return;
        if (result.status == BackupTransferStatus.success) {
          navigator.currentState!.popUntil((route) => route.isFirst);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            feedback(navigator.currentContext!, 'バックアップから復元しました');
            setState(() => successNotificationId++);
          });
        } else if (result.saveFailure?.uncertain != true) {
          feedback(navigator.currentContext!, transferError(result));
        }
        return;
      }
    } catch (_) {
      if (mounted) feedback(navigator.currentContext!, generalError);
    }
  }

  Future<void> startNew(BuildContext context) async {
    if (state.phase == StartupPhase.failure) {
      if (!await confirm(
        context,
        '新しく設定しますか？',
        '現在読み込めない保存データは削除され、元に戻せません。',
        '削除して新しく設定する',
        destructive: true,
      )) {
        return;
      }
      if (!context.mounted) return;
      try {
        await state.discardFailureAndStartNew();
      } on SaveRequestFailure catch (error) {
        if (mounted && !error.uncertain) {
          feedback(navigator.currentContext!, generalError);
        }
        return;
      } catch (_) {
        if (mounted) feedback(navigator.currentContext!, generalError);
        return;
      }
    }
    if (mounted && state.phase == StartupPhase.noData) {
      setState(() => settingUp = true);
    }
  }

  void openDataManagement() => navigator.currentState!.push<void>(
    MaterialPageRoute(
      builder: (_) =>
          DataManagementScreen(onExport: export, onRestore: restore),
    ),
  );

  Widget message(String title, String text, {String? button}) => Scaffold(
    appBar: AppBar(title: const Text('Keep My Car')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title),
            const SizedBox(height: 24),
            Text(text),
            if (button != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: state.load, child: Text(button)),
            ],
          ],
        ),
      ),
    ),
  );
  Widget home() => switch (state.phase) {
    StartupPhase.loading => message('データを読み込んでいます…', ''),
    StartupPhase.noData =>
      settingUp
          ? InitialSetupScreen(
              referenceMonth: state.referenceMonth,
              onSave:
                  ({
                    required ownerBirthMonth,
                    required car,
                    required conditions,
                  }) => state.initialize((
                    ownerBirthMonth: ownerBirthMonth,
                    car: car,
                    planConditions: conditions,
                    plannedExpenses: [],
                  )),
            )
          : DataManagementScreen(onRestore: restore, onStartNew: startNew),
    StartupPhase.failure => DataManagementScreen(
      failure: true,
      onRestore: restore,
      onStartNew: startNew,
      onReload: state.load,
    ),
    StartupPhase.uncertain => message(
      '保存状態を確認できませんでした',
      '保存中に問題が発生したため、実際に保存されているデータを確認する必要があります。',
      button: '保存状態を確認する',
    ),
    StartupPhase.ready || StartupPhase.recovered => HomeScreen(
      car: state.car!,
      onDataManagement: openDataManagement,
      session: state.session!,
      onSaveCarName: state.saveCarName,
      onApply: state.apply,
      onSaveExpense: state.saveExpense,
      onDeleteExpense: state.deleteExpense,
      onNavigate: () => setState(state.session!.consumeHomeUpdate),
      onTimelineViewed: () => setState(state.session!.acknowledgeTimeline),
      onReserveViewed: () => setState(state.session!.acknowledgeReserve),
      onExpensesChanged: () => setState(() {}),
    ),
  };
  @override
  void dispose() {
    state.removeListener(changed);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    title: 'Keep My Car',
    locale: const Locale('ja', 'JP'),
    supportedLocales: const [Locale('ja', 'JP')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light,
    themeMode: ThemeMode.light,
    home: ScreenSuccessFeedback(
      notificationId: successNotificationId,
      child: home(),
    ),
  );
}
