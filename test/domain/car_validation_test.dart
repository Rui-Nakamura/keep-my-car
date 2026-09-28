import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/car_validation.dart';

void main() {
  test('normalizes outer whitespace and preserves internal whitespace', () {
    expect(validateCarName('　 メルセデスAMG E53  '), (
      name: 'メルセデスAMG E53',
      error: null,
    ));
    expect(validateCarName(' A　 B  C ').name, 'A　 B  C');
  });
  test('accepts one and forty code points, rejects forty-one', () {
    for (final name in ['車', '車' * 40, '🚗' * 40]) {
      expect(validateCarName('　$name ').error, isNull);
    }
    for (final name in ['車' * 41, '🚗' * 41, 'e\u0301' * 21]) {
      expect(validateCarName(name).error, CarNameError.tooLong);
    }
    expect(validateCarName('e\u0301' * 20).error, isNull);
  });
  test('rejects empty and whitespace-only input', () {
    for (final name in ['', ' ', '　']) {
      expect(validateCarName(name).error, CarNameError.required);
    }
  });
  for (final control in ['\r', '\n', '\r\n', '\t']) {
    test('rejects control ${control.codeUnits} before trimming', () {
      for (final input in [
        'メルセデス${control}AMG E53',
        '$control愛車',
        '愛車$control',
        control,
      ]) {
        expect(validateCarName(input).error, CarNameError.invalidCharacters);
      }
    });
  }
  test('ordinary internal spaces remain valid', () {
    expect(validateCarName('メルセデス AMG E53'), (
      name: 'メルセデス AMG E53',
      error: null,
    ));
  });
}
