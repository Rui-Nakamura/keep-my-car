import 'package:flutter_test/flutter_test.dart';
import 'package:keep_my_car/domain/models/year_month.dart';
import 'package:keep_my_car/domain/planned_expense_validation.dart';

void main() {
  Map<ExpenseField, ExpenseInputError> validate({
    String name = '車検',
    String amount = '0',
    YearMonth month = const YearMonth(2026, 9),
  }) => validatePlannedExpense(
    name: name,
    amount: amount,
    month: month,
    referenceMonth: const YearMonth(2026, 9),
    ownershipTargetMonth: const YearMonth(2040, 4),
  );

  for (final name in ['', ' ', '　', ' 　\t ']) {
    test('reject empty normalized name "$name"', () {
      expect(
        validate(name: name)[ExpenseField.name],
        ExpenseInputError.required,
      );
    });
  }
  test('name limit after trim; internal whitespace retained by validation', () {
    expect(validate(name: '　${'車' * 40}  '), isEmpty);
    expect(
      validate(name: '車' * 41)[ExpenseField.name],
      ExpenseInputError.tooLong,
    );
    expect(validate(name: '車検　 と 点検'), isEmpty);
  });
  for (final amount in ['0', '1000000000']) {
    test(
      'amount boundary $amount accepted',
      () => expect(validate(amount: amount), isEmpty),
    );
  }
  for (final amount in [
    '',
    '-1',
    '1.5',
    'abc',
    '1e3',
    '1000000001',
    '99999999999999999999999999',
  ]) {
    test('invalid amount "$amount" rejected', () {
      expect(validate(amount: amount), contains(ExpenseField.amount));
    });
  }
  for (final month in [const YearMonth(2026, 9), const YearMonth(2040, 4)]) {
    test(
      'inclusive month boundary $month accepted',
      () => expect(validate(month: month), isEmpty),
    );
  }
  for (final month in [const YearMonth(2026, 8), const YearMonth(2040, 5)]) {
    test('outside month $month rejected', () {
      expect(
        validate(month: month)[ExpenseField.month],
        ExpenseInputError.outOfRange,
      );
    });
  }
}
