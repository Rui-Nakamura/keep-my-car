import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';

class PlanSettingsScreen extends StatelessWidget {
  const PlanSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('計画設定')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final heading in const [
                '愛車',
                'オーナー',
                '保有目標',
                '現在の愛車資金',
                '普段の維持費',
                'バックアップ',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.section),
                  child: Semantics(
                    header: true,
                    child: Text(heading, style: text.titleLarge),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
