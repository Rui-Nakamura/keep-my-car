import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/save_restriction.dart';
import 'package:keep_my_car/features/car/presentation/car_name_screen.dart';
import 'package:keep_my_car/features/home/presentation/home_screen.dart';
import 'package:keep_my_car/features/settings/presentation/data_management_screen.dart';
import 'package:keep_my_car/features/settings/presentation/plan_settings_screen.dart';
import 'package:keep_my_car/features/timeline/presentation/future_timeline_screen.dart';
import 'package:keep_my_car/persistence/persistence_result.dart';
import 'package:keep_my_car/photo/photo_library.dart';

import 'app/plan_summary_test.dart' show expense;
import 'home_car_photo_test.dart' show ControlledPhotos, finishImage;
import 'home_test_support.dart';
import 'persistence_app_support.dart';
import 'photo/photo_test_support.dart';
import 'plan_test_support.dart';

void viewport(WidgetTester tester, double width, double scale) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

RenderParagraph homeParagraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void expectPaintedNumberFits(WidgetTester tester, Finder text) {
  final paragraph = homeParagraph(tester, text);
  final label = paragraph.text.toPlainText();
  expect(paragraph.locale, Localizations.maybeLocaleOf(tester.element(text)));
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textHeightBehavior: paragraph.textHeightBehavior,
    textWidthBasis: paragraph.textWidthBasis,
  )..layout();
  try {
    expect(
      painter.width,
      lessThanOrEqualTo(paragraph.size.width + 0.1),
      reason: '$label must fit at its actual font, locale and TextScaler',
    );
    for (var offset = 0; offset < label.length; offset++) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      );
      expect(boxes, isNotEmpty, reason: '$label offset $offset');
      for (final box in boxes) {
        expect(box.left, greaterThanOrEqualTo(-0.1));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.1));
      }
    }
  } finally {
    painter.dispose();
  }
}

void main() {
  setUpAll(loadHomeJapaneseFont);

  for (final settings in [
    (400.0, 1.0),
    (360.0, 1.0),
    (360.0, 2.0),
    (360.0, 3.0),
  ]) {
    testWidgets('Home UX phrases, accessibility and bounds / $settings', (
      tester,
    ) async {
      viewport(tester, settings.$1, settings.$2);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(testApp());
        await tester.pumpAndSettle();
        expect(find.byType(Banner), findsNothing);
        expect(find.text('70歳'), findsOneWidget);
        expect(find.text('21年'), findsOneWidget);
        expect(find.text('99,333km'), findsOneWidget);
        expect(find.text('2,550,000円'), findsOneWidget);
        expect(find.text('80,000円'), findsNWidgets(2));
        expect(find.text('300,000円'), findsOneWidget);
        expect(find.text('2040年4月まで'), findsOneWidget);
        expect(find.text('2027年4月'), findsOneWidget);
        expect(find.text('12Vバッテリー'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Text && widget.semanticsLabel == '2027年の予定費',
          ),
          findsOneWidget,
        );
        final summaries = [
          for (final title in ['次の予定費', '来年', '今後5年間'])
            find.byKey(ValueKey('home-summary-$title')),
        ];
        final rects = summaries.map(tester.getRect).toList();
        if (settings.$2 == 1) {
          expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
          expect(rects.map((rect) => rect.height).toSet(), hasLength(1));
          expect(rects[0].right, lessThan(rects[1].left));
          expect(rects[1].right, lessThan(rects[2].left));
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('home-photo-unset')))
                .dx,
            greaterThan(tester.getTopLeft(find.text('70歳')).dx),
          );
          if (settings.$1 == 360) {
            for (var i = 0; i < summaries.length; i++) {
              final icon = find
                  .descendant(of: summaries[i], matching: find.byType(Icon))
                  .first;
              final title = find.descendant(
                of: summaries[i],
                matching: find.text(['次の予定費', '来年', '今後5年間'][i]),
              );
              expect(
                tester.getRect(icon).bottom,
                lessThan(tester.getRect(title).top),
              );
            }
          }
        } else {
          expect(rects.map((rect) => rect.left).toSet(), hasLength(1));
          expect(rects.map((rect) => rect.width).toSet(), hasLength(1));
          expect(rects[0].bottom, lessThan(rects[1].top));
          expect(rects[1].bottom, lessThan(rects[2].top));
        }
        final catchphrase = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '好きな車に、あと何年乗れる？',
        );
        final copy = tester.widget<Text>(catchphrase).data!;
        expect(copy.replaceAll('\n', ''), '好きな車に、あと何年乗れる？');
        expect(
          tester.getSemantics(catchphrase).getSemanticsData().label,
          '好きな車に、あと何年乗れる？',
        );
        if (settings.$2 == 1) expect(copy, isNot(contains('\n')));
        final copyParagraph = homeParagraph(tester, catchphrase);
        final lineTops = <double>{};
        for (final phrase in ['好きな車に、', 'あと何年', '乗れる？']) {
          final start = copy.indexOf(phrase);
          expect(start, greaterThanOrEqualTo(0));
          final boxes = copyParagraph.getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + phrase.length,
            ),
          );
          expect(boxes, isNotEmpty);
          expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(-0.1));
            expect(
              box.right,
              lessThanOrEqualTo(copyParagraph.size.width + 0.1),
            );
          }
          lineTops.addAll(boxes.map((box) => box.top));
        }
        expect(lineTops.length, settings.$2 == 1 ? 1 : greaterThan(1));
        final numbers = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan != null &&
              widget.softWrap == false,
        );
        expect(numbers, findsNWidgets(7));
        for (final number in numbers.evaluate()) {
          expectPaintedNumberFits(tester, find.byWidget(number.widget));
        }
        final description = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.semanticsLabel == '2026年〜2030年の予定費の合計',
        );
        final descriptionText = tester.widget<Text>(description).data!;
        final descriptionParagraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: description, matching: find.byType(RichText)),
        );
        for (final phrase in ['の予定費', 'の合計']) {
          final offset = descriptionText.indexOf(phrase);
          final boxes = descriptionParagraph.getBoxesForSelection(
            TextSelection(
              baseOffset: offset,
              extentOffset: offset + phrase.length,
            ),
          );
          expect(boxes.map((box) => box.top).toSet(), hasLength(1));
        }
        final actions = {
          '＋ 予定費を追加する': ['予定費を', '追加する'],
          '未来タイムラインを見る': ['タイムライン', 'を見る'],
          '愛車予定費を見る': ['愛車予定費', 'を見る'],
          '愛車の計画を見直す': ['愛車の計画を', '見直す'],
        };
        for (final action in actions.entries) {
          final label = homeActionLabel(action.key);
          await tester.ensureVisible(label);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(label).getSemanticsData().label,
            action.key,
          );
          final text = find
              .descendant(of: label, matching: find.byType(Text))
              .last;
          final value = tester.widget<Text>(text).data!;
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          for (final phrase in action.value) {
            final offset = value.indexOf(phrase);
            expect(offset, greaterThanOrEqualTo(0));
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: offset,
                extentOffset: offset + phrase.length,
              ),
            );
            expect(
              boxes.map((box) => box.top).toSet(),
              hasLength(1),
              reason: '$phrase must remain on one visual line',
            );
          }
          final button = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(settings.$1));
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('whole expense summary is tappable outside its text', (
    tester,
  ) async {
    viewport(tester, 360, 3);
    final repo = TestRepository(Loaded(sampleSnapshot()));
    await tester.pumpWidget(
      KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
    );
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('home-summary-次の予定費'));
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();
    final rect = tester.getRect(summary);
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 8));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '愛車予定費'), findsOneWidget);
    expect(repo.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal width keeps three aligned summaries and target beside photo',
    (tester) async {
      viewport(tester, 800, 1);
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();
      final titles = ['次の予定費', '来年', '今後5年間'];
      final y = tester.getTopLeft(find.text(titles.first)).dy;
      final heights = <double>[];
      for (final title in titles) {
        expect(tester.getTopLeft(find.text(title)).dy, y);
        heights.add(
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(title),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .height,
        );
      }
      expect(heights.toSet(), hasLength(1));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-photo-unset'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('home-target-age'))).dx,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final corrupt in [false, true]) {
    testWidgets(
      'unreadable photo retains Home values, navigation and formal reference / $corrupt',
      (tester) async {
        final calls = CalculationCalls();
        final plan = session(
          timelineCalculator: calls.calculateTimeline,
          reserveCalculator: calls.calculateReserve,
        );
        final snapshot = sampleSnapshot(plan);
        final repo = TestRepository(
          Loaded((
            photoId: photoA,
            ownerBirthMonth: snapshot.ownerBirthMonth,
            car: snapshot.car,
            planConditions: snapshot.planConditions,
            plannedExpenses: snapshot.plannedExpenses,
          )),
        );
        final storage = MemoryPhotos();
        if (corrupt) storage.files[photoA] = Uint8List.fromList([1, 2, 3]);
        final photos = PhotoLibrary(
          storage: storage,
          processor: FakeProcessor(),
        );
        calls.reset();
        await tester.pumpWidget(
          KeepMyCarApp(
            repository: repo,
            photos: photos,
            now: () => DateTime(2026, 9),
            sessionFactory: (_, _) => plan,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-photo-unavailable')),
          findsOneWidget,
        );
        expect(find.text('99,333km'), findsOneWidget);
        expect(find.text('2,550,000円'), findsOneWidget);
        expect(
          tester.widget<HomeScreen>(find.byType(HomeScreen)).photoId,
          photoA,
        );
        await tester.ensureVisible(find.text('未来タイムラインを見る'));
        await tester.tap(find.text('未来タイムラインを見る'));
        await tester.pumpAndSettle();
        expect(find.byType(FutureTimelineScreen), findsOneWidget);
        expect(repo.saves, isEmpty);
        expect(storage.sweeps, isEmpty);
        expect((calls.timeline, calls.reserve), (0, 0));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 3.0]) {
    testWidgets(
      'menu order, disabled photo, dismissal and live restrictions / $scale',
      (tester) async {
        viewport(tester, 360, scale);
        final plan = session();
        plan.apply(conditions(annual: 6000));
        final update = plan.homeUpdate;
        final pending = plan.timelinePending;
        await tester.pumpWidget(testApp(session: plan));
        await tester.pumpAndSettle();
        await openHomeMenu(tester);
        final entries = tester
            .widgetList<PopupMenuItem>(
              find.byWidgetPredicate((widget) => widget is PopupMenuItem),
            )
            .toList();
        expect(entries.map((e) => (e.child! as Text).data), [
          '愛車の写真',
          '愛車名を編集',
          '愛車の計画を見直す',
          'データ管理',
        ]);
        expect(entries.first.enabled, isFalse);
        expect(plan.homeUpdate, update);
        expect(plan.timelinePending, pending);
        for (final entry
            in find
                .byWidgetPredicate((widget) => widget is PopupMenuItem)
                .evaluate()) {
          expect(
            tester.getSize(find.byWidget(entry.widget)).height,
            greaterThanOrEqualTo(48),
          );
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(plan.homeUpdate, update);
        expect(plan.timelinePending, pending);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final destination in [
    ('愛車名を編集', CarNameScreen),
    ('愛車の計画を見直す', PlanSettingsScreen),
    ('データ管理', DataManagementScreen),
  ]) {
    testWidgets(
      'menu ${destination.$1} uses existing destination and returns Home',
      (tester) async {
        final calls = CalculationCalls();
        final plan = session(
          timelineCalculator: calls.calculateTimeline,
          reserveCalculator: calls.calculateReserve,
        );
        final repo = TestRepository(Loaded(sampleSnapshot(plan)));
        await tester.pumpWidget(
          KeepMyCarApp(
            repository: repo,
            now: () => DateTime(2026, 9),
            sessionFactory: (_, _) => plan,
          ),
        );
        await tester.pumpAndSettle();
        calls.reset();
        await tapHomeMenuItem(tester, destination.$1);
        expect(find.byType(destination.$2), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect((calls.timeline, calls.reserve), (0, 0));
        expect(repo.saves, isEmpty);
      },
    );
  }

  testWidgets(
    'save restriction disables menu name and direct add, preserves viewing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SaveRestriction(
            restricted: true,
            child: Builder(
              builder: (context) {
                final plan = session();
                return HomeScreen(
                  car: sampleSnapshot(plan).car,
                  session: plan,
                  onSaveCarName: (_) => null,
                  onApply: (_) => {},
                  onNavigate: () {},
                  onTimelineViewed: () {},
                  onReserveViewed: () {},
                  onExpensesChanged: () {},
                  onSaveExpense: ({
                    id,
                    required name,
                    required month,
                    required amountYen,
                  }) => throw StateError('must not save'),
                  onDeleteExpense: (_) => throw StateError('must not delete'),
                  onDataManagement: () {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '＋ 予定費を追加する'),
            )
            .onPressed,
        isNull,
      );
      await openHomeMenu(tester);
      final items = tester
          .widgetList<PopupMenuItem>(
            find.byWidgetPredicate((widget) => widget is PopupMenuItem),
          )
          .toList();
      expect(items[1].enabled, isFalse);
      expect(items[2].enabled, isTrue);
      expect(items[3].enabled, isTrue);
    },
  );

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 3.0]) {
      testWidgets(
        'long whole numbers and 40-character name remain visible / $width / $scale',
        (tester) async {
          viewport(tester, width, scale);
          final plan = session(
            initial: conditions(ownership: 100),
            expenses: [expense(1, 2027, 4, 1000000000)],
          );
          final snapshot = sampleSnapshot(plan);
          final repo = TestRepository(
            Loaded((
              photoId: null,
              ownerBirthMonth: snapshot.ownerBirthMonth,
              car: snapshot.car.copyWith(name: '車' * 40),
              planConditions: snapshot.planConditions,
              plannedExpenses: snapshot.plannedExpenses,
            )),
          );
          await tester.pumpWidget(
            KeepMyCarApp(repository: repo, now: () => DateTime(2026, 9)),
          );
          await tester.pumpAndSettle();
          expect(find.text('100歳'), findsOneWidget);
          expect(find.text('1,000,000,000円'), findsNWidgets(4));
          for (final number in find.text('1,000,000,000円').evaluate()) {
            expectPaintedNumberFits(tester, find.byWidget(number.widget));
          }
          expect(find.text('車' * 40), findsOneWidget);
          // Large amounts must get full-width summary rows instead of tiny columns.
          expect(
            tester.getTopLeft(find.text('次の予定費')).dx,
            tester.getTopLeft(find.text('来年')).dx,
          );
          for (final element in find.byType(RichText).evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
          }
          for (final label in [
            '＋ 予定費を追加する',
            '未来タイムラインを見る',
            '愛車予定費を見る',
            '愛車の計画を見直す',
          ]) {
            await tester.ensureVisible(homeControl(label));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(homeControl(label)).right,
              lessThanOrEqualTo(width),
            );
          }
          expect(tester.takeException(), isNull);
          expect(repo.saves, isEmpty);
        },
      );
    }
  }

  testWidgets(
    'App passes formal photo ID and shared Library without saving or calculating',
    (tester) async {
      final calls = CalculationCalls();
      final plan = session(
        timelineCalculator: calls.calculateTimeline,
        reserveCalculator: calls.calculateReserve,
      );
      final snapshot = sampleSnapshot(plan);
      final repo = TestRepository(
        Loaded((
          photoId: photoA,
          ownerBirthMonth: snapshot.ownerBirthMonth,
          car: snapshot.car,
          planConditions: snapshot.planConditions,
          plannedExpenses: snapshot.plannedExpenses,
        )),
      );
      final photos = ControlledPhotos((_) async => smallJpeg());
      calls.reset();
      await tester.pumpWidget(
        KeepMyCarApp(
          repository: repo,
          photos: photos,
          now: () => DateTime(2026, 9),
          sessionFactory: (_, _) => plan,
        ),
      );
      await tester.pumpAndSettle();
      await finishImage(tester);
      final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(home.photoId, photoA);
      expect(home.photos, same(photos));
      expect(photos.reads, [photoA]);
      expect(find.text('99,333km'), findsOneWidget);
      expect(find.text('2,550,000円'), findsOneWidget);
      expect((calls.timeline, calls.reserve), (0, 0));
      expect(repo.saves, isEmpty);
      expect(repo.discards, 0);
      expect((photos.storage as MemoryPhotos).sweeps, isEmpty);
      await openHomeMenu(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(photos.reads, [photoA]);
    },
  );
}
