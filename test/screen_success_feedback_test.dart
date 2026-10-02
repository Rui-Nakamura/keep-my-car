import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/screen_success_feedback.dart';

void main() {
  final outline = find.byKey(const ValueKey('screen-success-outline'));
  Widget screen(int event, {bool reduceMotion = false, VoidCallback? onTap}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: ScreenSuccessFeedback(
            notificationId: event,
            child: Scaffold(
              body: Center(
                child: TextButton(onPressed: onTap, child: const Text('操作')),
              ),
            ),
          ),
        ),
      );

  testWidgets('one event is consumed once; rebuild and remount do not replay', (
    tester,
  ) async {
    await tester.pumpWidget(screen(0));
    expect(outline, findsNothing);
    await tester.pumpWidget(screen(1));
    expect(outline, findsOneWidget);
    await tester.pumpAndSettle();
    expect(outline, findsNothing);
    await tester.pumpWidget(screen(1));
    expect(outline, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen(1));
    expect(outline, findsNothing);
    await tester.pumpWidget(screen(2));
    expect(outline, findsOneWidget);
    await tester.pumpAndSettle();
    expect(outline, findsNothing);
  });

  testWidgets('outline does not intercept a tap while visible', (tester) async {
    var taps = 0;
    await tester.pumpWidget(screen(0, onTap: () => taps++));
    await tester.pumpWidget(screen(1, onTap: () => taps++));
    expect(outline, findsOneWidget);
    await tester.tap(find.text('操作'));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion shows a finite static outline without a ticker', (
    tester,
  ) async {
    await tester.pumpWidget(screen(0, reduceMotion: true));
    await tester.pumpWidget(screen(1, reduceMotion: true));
    expect(outline, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    // Only an upper bound, not an exact animation timeline contract.
    await tester.pump(const Duration(seconds: 3));
    expect(outline, findsNothing);
    await tester.pumpWidget(screen(1, reduceMotion: true));
    expect(outline, findsNothing);
  });
}
