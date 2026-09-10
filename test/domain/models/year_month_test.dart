import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/year_month.dart';

void main() {
  test('Can construct a const calendar month', () {
    const month = YearMonth(2026, 9);
    expect(month.year, 2026);
    expect(month.month, 9);
    expect(month.toString(), '2026-09');
  });

  test('Equal values have equal hashes and work as set keys', () {
    const first = YearMonth(2026, 9);
    final second = YearMonth(2026, 9);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect({first, second}, hasLength(1));
    expect(first == const YearMonth(2026, 10), isFalse);
    expect(first == const YearMonth(2027, 9), isFalse);
    expect(first == Object(), isFalse);
  });

  test('Orders across years and within the same year', () {
    expect(
      const YearMonth(2027, 4).compareTo(const YearMonth(2028, 8)),
      isNegative,
    );
    expect(
      const YearMonth(2028, 8).compareTo(const YearMonth(2027, 4)),
      isPositive,
    );
    expect(
      const YearMonth(2026, 9).compareTo(const YearMonth(2026, 10)),
      isNegative,
    );
    expect(
      const YearMonth(2026, 10).compareTo(const YearMonth(2026, 9)),
      isPositive,
    );
    expect(
      const YearMonth(2026, 9).compareTo(const YearMonth(2026, 9)),
      isZero,
    );
    expect(
      const YearMonth(2026, 12).compareTo(const YearMonth(2027, 1)),
      isNegative,
    );
  });

  for (final month in [0, 13]) {
    test('Rejects month $month with an assertion', () {
      expect(() => YearMonth(2026, month), throwsAssertionError);
    });
  }

  test('Accepts boundary months', () {
    expect(const YearMonth(2026, 1).month, 1);
    expect(const YearMonth(2026, 12).month, 12);
  });
}
