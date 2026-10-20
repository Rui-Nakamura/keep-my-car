import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/initial_setup/presentation/initial_setup_screen.dart';
import 'package:keep_my_car/persistence/keep_my_car_repository.dart';
import 'package:keep_my_car/persistence/local_file_storage.dart';

void main() {
  testWidgets(
    'real files: NoData setup save, dispose app, new app loads all fields',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('kmc_app_e3c_'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );

      KeepMyCarApp app() => KeepMyCarApp(
        repository: KeepMyCarRepository(
          IoLocalFileStorage(directory: () async => directory),
        ),
        now: () => DateTime(2026, 9, 30),
      );
      // Real I/O must progress outside the widget test's fake async clock.
      Future<void> waitFor(Finder target) async {
        for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(target, findsOneWidget);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(app());
      await waitFor(find.text('新しく設定する'));
      await tester.tap(find.text('新しく設定する'));
      await tester.pumpAndSettle();
      await waitFor(find.byType(InitialSetupScreen));
      expect(find.byType(HomeScreen), findsNothing);
      for (final entry in {
        'birth': '1975-06',
        'name': 'FileIntegrationCar',
        'registration': '2019-03',
        'mileage': '54321',
        'checked': '2026-08',
        'annual': '6789',
        'ownership': '72',
      }.entries) {
        final field = find.byKey(ValueKey('setup-${entry.key}'));
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('setup-save'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await waitFor(find.byType(HomeScreen));

      final json = await tester.runAsync(
        () async => jsonDecode(
          await File(
            '${directory.path}${Platform.pathSeparator}${DataFile.current.fileName}',
          ).readAsString(),
        ) as Map<String, dynamic>,
      );
      expect(json, {
        // New setup writes internal v3, including an explicit unset reference.
        'formatVersion': 3,
        'photoId': null,
        'ownerBirthMonth': '1975-06',
        'car': {
          'name': 'FileIntegrationCar',
          'firstRegistrationMonth': '2019-03',
          'currentMileageKm': 54321,
          'mileageCheckedMonth': '2026-08',
          'annualMileageKm': 6789,
        },
        'planConditions': {
          'fundingPlanEnabled': false,
          'currentMileageKm': 54321,
          'annualMileageKm': 6789,
          'ownershipTargetAge': 72,
          'currentCarFundYen': 0,
          'reserveTargetAge': 0,
          'largeRepairReserveYen': 0,
        },
        'plannedExpenses': [],
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await waitFor(find.byType(HomeScreen));
      expect(find.byType(InitialSetupScreen), findsNothing);
      final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(home.session.birthMonth, const YearMonth(1975, 6));
      expect(home.car.name, 'FileIntegrationCar');
      expect(home.car.firstRegistrationMonth, const YearMonth(2019, 3));
      expect(home.car.currentMileageKm, 54321);
      expect(home.car.mileageCheckedMonth, const YearMonth(2026, 8));
      expect(home.car.annualMileageKm, 6789);
      final plan = home.session.conditions;
      expect(plan.currentMileageKm, 54321);
      expect(plan.annualMileageKm, 6789);
      expect(plan.ownershipTargetAge, 72);
      expect(plan.currentCarFundYen, 0);
      expect(plan.fundingPlanEnabled, false);
      expect(plan.reserveTargetAge, 0);
      expect(plan.largeRepairReserveYen, 0);
      expect(home.session.plannedExpenses, isEmpty);
      expect(home.session.referenceMonth, const YearMonth(2026, 9));
      expect(find.text('FileIntegrationCar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
