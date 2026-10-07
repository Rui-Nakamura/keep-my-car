import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_app_support.dart';

import 'package:keep_my_car/app/update_feedback.dart';
import 'package:keep_my_car/domain/models/major_repair_reserve.dart';
import 'package:keep_my_car/domain/models/ownership_goal.dart';
import 'package:keep_my_car/domain/repair_reserve_calculator.dart';
import 'package:keep_my_car/features/repair_reserve/presentation/repair_reserve_screen.dart';
import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';

import 'plan_test_support.dart';
import 'plan_settings_screen_test.dart' show openSettings, enter, apply;

double timelineAlpha(WidgetTester tester) => tester
    .widget<Container>(find.byKey(const ValueKey('timeline-emphasis-2026')))
    .color!
    .a;
double reserveAlpha(WidgetTester tester) =>
    (tester
                .widget<Container>(
                  find.byKey(const ValueKey('reserve-emphasis')),
                )
                .decoration!
            as BoxDecoration)
        .border!
        .top
        .color
        .a;

void main() {
  for (final timeline in [true, false]) {
    testWidgets(
      '${timeline ? 'timeline' : 'reserve'} reduced motion toggled during fade does not leave or restart emphasis',
      (tester) async {
        final plan = session();
        var reduceMotion = false;
        var acknowledgements = 0;
        late StateSetter update;
        final screen = timeline
            ? FutureTimelineScreen(
                years: plan.timeline,
                updatePending: true,
                onViewed: () => acknowledgements++,
              )
            : RepairReserveScreen(
                ownershipGoal: const OwnershipGoal(targetAge: 70),
                reserve: const MajorRepairReserve(
                  amountYen: 2000000,
                  targetAge: 65,
                ),
                result: plan.reserveResult,
                updatePending: true,
                onViewed: () => acknowledgements++,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQueryData(disableAnimations: reduceMotion),
                  child: screen,
                );
              },
            ),
          ),
        );
        final alpha = timeline ? timelineAlpha : reserveAlpha;
        final initial = alpha(tester);
        expect(initial, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 800));
        expect(alpha(tester), greaterThan(0));
        expect(alpha(tester), lessThan(initial));

        update(() => reduceMotion = true);
        await tester.pump();
        expect(alpha(tester), initial);
        await tester.pump(const Duration(milliseconds: 100));
        expect(alpha(tester), initial);
        expect(tester.binding.transientCallbackCount, 0);

        update(() => reduceMotion = false);
        await tester.pump();
        expect(alpha(tester), 0);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(milliseconds: 800));
        expect(alpha(tester), 0);
        await tester.pump(const Duration(seconds: 2));
        expect(alpha(tester), 0);
        expect(acknowledgements, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${timeline ? 'timeline' : 'reserve'} fades once, snapshot survives rebuild and acknowledgement',
      (tester) async {
        final plan = session();
        var acknowledgements = 0;
        VoidCallback rebuild = () {};
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = () => setState(() {});
                return timeline
                    ? FutureTimelineScreen(
                        years: plan.timeline,
                        updatePending: true,
                        onViewed: () {
                          acknowledgements++;
                        },
                      )
                    : RepairReserveScreen(
                        ownershipGoal: const OwnershipGoal(targetAge: 70),
                        reserve: const MajorRepairReserve(
                          amountYen: 2000000,
                          targetAge: 65,
                        ),
                        result: plan.reserveResult,
                        updatePending: true,
                        deltaYen: -1500,
                        onViewed: () {
                          acknowledgements++;
                        },
                      );
              },
            ),
          ),
        );
        final alpha = timeline ? timelineAlpha : reserveAlpha;
        final initial = alpha(tester);
        expect(initial, greaterThan(0));
        expect(acknowledgements, 1);
        await tester.pump(const Duration(milliseconds: 800));
        final middle = alpha(tester);
        expect(middle, greaterThan(0));
        expect(middle, lessThan(initial));
        rebuild();
        await tester.pump();
        expect(alpha(tester), closeTo(middle, 0.001));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(alpha(tester), 0);
        rebuild();
        await tester.pump(const Duration(milliseconds: 100));
        expect(alpha(tester), 0);
        expect(acknowledgements, 1);
        if (!timeline) expect(find.text('前回の試算より −1,500円 / 月'), findsOneWidget);
      },
    );

    testWidgets(
      '${timeline ? 'timeline' : 'reserve'} reduced motion stays static',
      (tester) async {
        final plan = session();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: timeline
                  ? FutureTimelineScreen(
                      years: plan.timeline,
                      updatePending: true,
                    )
                  : RepairReserveScreen(
                      ownershipGoal: const OwnershipGoal(targetAge: 70),
                      reserve: const MajorRepairReserve(
                        amountYen: 2000000,
                        targetAge: 65,
                      ),
                      result: plan.reserveResult,
                      updatePending: true,
                      deltaYen: 10,
                    ),
            ),
          ),
        );
        final alpha = timeline ? timelineAlpha : reserveAlpha;
        final initial = alpha(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(alpha(tester), initial);
        expect(initial, greaterThan(0));
        expect(
          find.byKey(
            ValueKey(timeline ? 'timeline-update-text' : 'reserve-update-text'),
          ),
          findsOneWidget,
        );
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'app snapshots, Home notice consumption, no-op and navigation never recalculate',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      await tester.pumpWidget(testApp(session: plan));
      await tester.pumpAndSettle();
      await openSettings(tester);
      calls.reset();
      await enter(tester, 'annualMileage', '6000');
      await enter(tester, 'fund', '1000000');
      await enter(tester, 'reserve', '3000000');
      await apply(tester);
      expect((calls.timeline, calls.reserve), (1, 1));
      expect(find.text('未来タイムラインを更新しました'), findsOneWidget);
      final savedDelta = plan.reserveDeltaYen;
      calls.reset();
      await tester.ensureVisible(find.text('未来タイムラインを見る'));
      await tester.tap(find.text('未来タイムラインを見る'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(plan.timelinePending, isFalse);
      expect(plan.reservePending, isTrue);
      expect(
        tester
            .widget<FutureTimelineScreen>(find.byType(FutureTimelineScreen))
            .updatePending,
        isTrue,
      );
      expect(timelineAlpha(tester), greaterThan(0));
      await tester.pump(const Duration(seconds: 2));
      expect(timelineAlpha(tester), 0);
      expect(
        find.byKey(const ValueKey('timeline-update-text')),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-update')), findsNothing);
      await openSettings(tester);
      await apply(tester);
      expect(plan.reservePending, isTrue);
      expect(plan.reserveDeltaYen, savedDelta);
      expect(find.byKey(const ValueKey('home-update')), findsNothing);
      await openReserveForTest(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(plan.reservePending, isFalse);
      expect(plan.reserveDeltaYen, isNull);
      expect(
        tester
            .widget<RepairReserveScreen>(find.byType(RepairReserveScreen))
            .deltaYen,
        savedDelta,
      );
      expect(find.byKey(const ValueKey('reserve-delta')), findsOneWidget);
      expect(reserveAlpha(tester), greaterThan(0));
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 100);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('reserve-delta')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(reserveAlpha(tester), 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      for (final link in ['未来タイムラインを見る', '詳しく見る']) {
        if (link == '詳しく見る') {
          await openReserveForTest(tester);
        } else {
          await tester.ensureVisible(find.text(link));
          await tester.tap(find.text(link));
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-update-text')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('reserve-update-text')), findsNothing);
        expect(find.byKey(const ValueKey('reserve-delta')), findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      expect((calls.timeline, calls.reserve), (0, 0));
    },
  );

  testWidgets('failure and zero delta never show fabricated difference', (
    tester,
  ) async {
    for (final result in [
      const RepairReserveFailure(RepairReserveError.invalidInput),
      session().reserveResult,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: RepairReserveScreen(
            ownershipGoal: const OwnershipGoal(targetAge: 70),
            reserve: const MajorRepairReserve(
              amountYen: 2000000,
              targetAge: 65,
            ),
            result: result,
            updatePending: true,
            deltaYen: result is RepairReserveFailure ? 999 : 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reserve-delta')), findsNothing);
      if (result is RepairReserveFailure) {
        expect(find.text('計算できません'), findsOneWidget);
        expect(find.text('大型修理込み'), findsNothing);
      }
    }
  });

  testWidgets(
    'disposing feedback cancels animation without repeating acknowledgement',
    (tester) async {
      var viewed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return const SizedBox();
            },
          ),
        ),
      );
      final widget = UpdateFeedback(
        pending: true,
        duration: const Duration(milliseconds: 1600),
        onViewed: () {
          viewed++;
        },
        builder: (_, emphasis) => const SizedBox(),
      );
      await tester.pumpWidget(MaterialApp(home: widget));
      expect(viewed, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(viewed, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
