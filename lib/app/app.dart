import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/models/year_month.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/initial_setup/presentation/initial_setup_screen.dart';
import '../persistence/keep_my_car_repository.dart';
import '../persistence/local_file_storage.dart';
import 'persistent_plan_state.dart';
import 'theme/app_theme.dart';

class KeepMyCarApp extends StatefulWidget {
  const KeepMyCarApp({
    super.key,
    this.repository,
    this.now,
    this.sessionFactory,
  });
  final KeepMyCarRepository? repository;
  final DateTime Function()? now;
  final SessionFactory? sessionFactory;
  @override
  State<KeepMyCarApp> createState() => _KeepMyCarAppState();
}

class _KeepMyCarAppState extends State<KeepMyCarApp> {
  final navigator = GlobalKey<NavigatorState>();
  late final PersistentPlanState state;
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
    StartupPhase.noData => InitialSetupScreen(
      referenceMonth: state.referenceMonth,
      onSave: ({required ownerBirthMonth, required car, required conditions}) =>
          state.initialize((
            ownerBirthMonth: ownerBirthMonth,
            car: car,
            planConditions: conditions,
            plannedExpenses: [],
          )),
    ),
    StartupPhase.failure => message(
      '保存データを読み込めませんでした',
      '保存されているデータは削除していません。',
      button: 'もう一度読み込む',
    ),
    StartupPhase.uncertain => message(
      '保存状態を確認できませんでした',
      '保存中に問題が発生したため、実際に保存されているデータを確認する必要があります。',
      button: '保存状態を確認する',
    ),
    StartupPhase.ready || StartupPhase.recovered => HomeScreen(
      car: state.car!,
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
    home: home(),
  );
}
