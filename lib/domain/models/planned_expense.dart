import 'year_month.dart';

enum ExpenseBasis { quoted, selfEstimate, placeholder }

enum PlannedExpenseStatus { planned, completed }

class PlannedExpense {
  const PlannedExpense({
    required this.name,
    required this.plannedMonth,
    required this.amountYen,
    required this.basis,
    required this.memo,
    required this.status,
  });

  final String name;
  final YearMonth plannedMonth;
  final int amountYen;
  final ExpenseBasis basis;
  final String? memo;
  final PlannedExpenseStatus status;
}
