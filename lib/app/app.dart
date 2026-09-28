import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/models/plan_conditions.dart';
import '../domain/models/car.dart';
import '../domain/car_validation.dart';
import '../domain/plan_conditions_validation.dart';
import '../features/home/presentation/home_screen.dart';
import '../sample_data/golden_sample.dart';
import 'plan_session.dart';
import 'theme/app_theme.dart';

class KeepMyCarApp extends StatefulWidget {
  const KeepMyCarApp({super.key, this.session});
  final PlanSession? session;

  @override
  State<KeepMyCarApp> createState() => _KeepMyCarAppState();
}

class _KeepMyCarAppState extends State<KeepMyCarApp> {
  late final PlanSession _session;
  late Car _car;

  @override
  void initState() {
    super.initState();
    _session =
        widget.session ??
        PlanSession(
          conditions: PlanConditions(
            currentMileageKm: goldenSample.car.currentMileageKm,
            annualMileageKm: goldenSample.car.annualMileageKm,
            ownershipTargetAge: goldenSample.goal.targetAge,
            currentCarFundYen: goldenSample.currentCarFundYen,
            reserveTargetAge: goldenSample.reserve.targetAge,
            largeRepairReserveYen: goldenSample.reserve.amountYen,
          ),
          birthMonth: goldenSample.owner.birthMonth,
          referenceMonth: goldenSample.referenceMonth,
          firstRegistrationMonth: goldenSample.car.firstRegistrationMonth,
          plannedExpenses: goldenSample.plannedExpenses,
        );
    _car = goldenSample.car.copyWith(
      currentMileageKm: _session.conditions.currentMileageKm,
      annualMileageKm: _session.conditions.annualMileageKm,
    );
  }

  Map<PlanField, PlanInputError> _apply(PlanConditions next) {
    final errors = _session.apply(next);
    if (errors.isEmpty) {
      setState(() {
        if (_car.currentMileageKm != _session.conditions.currentMileageKm ||
            _car.annualMileageKm != _session.conditions.annualMileageKm) {
          _car = _car.copyWith(
            currentMileageKm: _session.conditions.currentMileageKm,
            annualMileageKm: _session.conditions.annualMileageKm,
          );
        }
      });
    }
    return errors;
  }

  CarNameError? _saveCarName(String input) {
    final result = validateCarName(input);
    if (result.error != null) return result.error;
    if (result.name != _car.name) {
      setState(() => _car = _car.copyWith(name: result.name));
    }
    return null;
  }

  void _update(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keep My Car',
    locale: const Locale('ja', 'JP'),
    supportedLocales: const [Locale('ja', 'JP')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light,
    themeMode: ThemeMode.light,
    home: HomeScreen(
      car: _car,
      onSaveCarName: _saveCarName,
      session: _session,
      onApply: _apply,
      onNavigate: () => _update(_session.consumeHomeUpdate),
      onTimelineViewed: () => _update(_session.acknowledgeTimeline),
      onReserveViewed: () => _update(_session.acknowledgeReserve),
      onExpensesChanged: () => _update(() {}),
    ),
  );
}
