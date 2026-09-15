import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/models/ownership_goal.dart';

class FutureTimelineScreen extends StatelessWidget {
  const FutureTimelineScreen({super.key, required this.goal});

  final OwnershipGoal goal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('未来タイムライン')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${goal.targetAge}歳までの計画', style: text.headlineLarge),
              const SizedBox(height: AppSpacing.lg),
              Text('これからの予定費と愛車の未来を時系列で確認できます。', style: text.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
