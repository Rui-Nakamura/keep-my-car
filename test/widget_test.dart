import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';

void main() {
  testWidgets('KeepMyCarApp uses the Japanese locale', (tester) async {
    await tester.pumpWidget(const KeepMyCarApp());
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('ja', 'JP'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('KeepMyCarApp starts and displays its name', (tester) async {
    await tester.pumpWidget(const KeepMyCarApp());

    expect(find.text('Keep My Car'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
