import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';
import 'package:keep_my_car/app/theme/app_theme.dart';

void main() {
  testWidgets('App stays light when the platform requests dark mode', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const KeepMyCarApp());

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F7F5));
  });

  testWidgets('Buttons and input grow with text scaling without overflow', (
    tester,
  ) async {
    Future<void> pumpControls(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Save')),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Cancel'),
                    ),
                    const TextField(
                      decoration: InputDecoration(labelText: 'Amount'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpControls(1);
    final filledHeight = tester.getSize(find.byType(FilledButton)).height;
    final outlinedHeight = tester.getSize(find.byType(OutlinedButton)).height;
    final inputHeight = tester.getSize(find.byType(TextField)).height;
    expect(filledHeight, greaterThanOrEqualTo(52));
    expect(outlinedHeight, greaterThanOrEqualTo(52));
    expect(inputHeight, greaterThanOrEqualTo(56));

    await pumpControls(3);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThan(filledHeight),
    );
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThan(outlinedHeight),
    );
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThan(inputHeight),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.fontSize,
      16,
    );
  });

  testWidgets('Multiline input grows as lines are entered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TextField(
              minLines: 1,
              maxLines: null,
              decoration: InputDecoration(labelText: 'Notes'),
            ),
          ),
        ),
      ),
    );
    final initialHeight = tester.getSize(find.byType(TextField)).height;
    await tester.enterText(
      find.byType(TextField),
      'First\nSecond\nThird\nFourth',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThan(initialHeight),
    );
    expect(tester.takeException(), isNull);
  });
}
