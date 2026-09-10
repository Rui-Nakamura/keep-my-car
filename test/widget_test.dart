import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/app/app.dart';

void main() {
  testWidgets('KeepMyCarApp starts and displays its name', (tester) async {
    await tester.pumpWidget(const KeepMyCarApp());

    expect(find.text('Keep My Car'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
