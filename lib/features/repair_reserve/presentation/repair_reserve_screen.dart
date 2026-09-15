import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/major_repair_reserve.dart';
import '../../home/presentation/home_format.dart';

class RepairReserveScreen extends StatelessWidget {
  const RepairReserveScreen({super.key, required this.reserve});

  final MajorRepairReserve reserve;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('大型修理への備え')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                formatReserveYen(reserve.amountYen),
                style: text.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('${reserve.targetAge}歳までに', style: text.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
