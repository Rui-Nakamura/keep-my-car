import 'models/year_month.dart';

enum ExpenseField { name, month, amount }

enum ExpenseInputError { required, tooLong, outOfRange, invalidInteger }

bool isExpenseMonthInRange(
  YearMonth month, {
  required YearMonth referenceMonth,
  required YearMonth ownershipTargetMonth,
}) =>
    month.compareTo(referenceMonth) >= 0 &&
    month.compareTo(ownershipTargetMonth) <= 0;

Map<ExpenseField, ExpenseInputError> validatePlannedExpense({
  required String name,
  required YearMonth month,
  required String amount,
  required YearMonth referenceMonth,
  required YearMonth ownershipTargetMonth,
}) {
  final errors = <ExpenseField, ExpenseInputError>{};
  final normalized = name.trim();
  if (normalized.isEmpty) {
    errors[ExpenseField.name] = ExpenseInputError.required;
  } else if (normalized.runes.length > 40) {
    errors[ExpenseField.name] = ExpenseInputError.tooLong;
  }
  if (!isExpenseMonthInRange(
    month,
    referenceMonth: referenceMonth,
    ownershipTargetMonth: ownershipTargetMonth,
  )) {
    errors[ExpenseField.month] = ExpenseInputError.outOfRange;
  }
  if (amount.isEmpty) {
    errors[ExpenseField.amount] = ExpenseInputError.required;
  } else if (!RegExp(r'^[0-9]+$').hasMatch(amount)) {
    errors[ExpenseField.amount] = ExpenseInputError.invalidInteger;
  } else {
    final value = int.tryParse(amount);
    if (value == null || value > 1000000000) {
      errors[ExpenseField.amount] = ExpenseInputError.outOfRange;
    }
  }
  return errors;
}
