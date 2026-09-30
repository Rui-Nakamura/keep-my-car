import 'dart:async';

import '../domain/models/year_month.dart';
import 'plan_session.dart';

/// Presentation-facing failure; screens do not need storage exception details.
class SaveRequestFailure implements Exception {
  const SaveRequestFailure({this.uncertain = false});
  final bool uncertain;
  static const message = '保存できませんでした。もう一度お試しください。';
}

typedef SaveExpenseRequest = FutureOr<ExpenseChange> Function({
  int? id,
  required String name,
  required YearMonth month,
  required int amountYen,
});
typedef DeleteExpenseRequest = FutureOr<ExpenseChange> Function(int id);
