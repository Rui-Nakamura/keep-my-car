import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/planned_expense.dart';

class PlannedExpensesScreen extends StatelessWidget {
  const PlannedExpensesScreen({super.key, required this.plannedExpenses});

  final List<PlannedExpense> plannedExpenses;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('愛車予定費')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${plannedExpenses.length}件の予定', style: text.headlineLarge),
            ],
          ),
        ),
      ),
    );
  }
}
