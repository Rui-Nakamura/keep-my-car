import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/update_feedback.dart';
import '../future_timeline_calculator.dart';
import '../../../domain/models/planned_expense.dart';
import '../../../domain/models/year_month.dart';
import '../../../app/display_format.dart';

// Route-local presentation colors; the shared app theme remains unchanged.
abstract final class _RoadmapColors {
  static const background = Color(0xFF071D2A);
  static const card = Color(0xFF103342);
  static const cardEnd = Color(0xFF0D2B39);
  static const border = Color(0xFF365F70);
  static const line = Color(0xFF739CAD);
  static const node = Color(0xFFA8C8D5);
  static const accent = Color(0xFF27B9C4);
  static const gold = Color(0xFFE5B44F);
  static const text = Color(0xFFF3F8FA);
  static const supporting = Color(0xFFBCD0DA);
  static const target = Color(0xFF293B3C);
}

class FutureTimelineScreen extends StatelessWidget {
  const FutureTimelineScreen({
    super.key,
    required this.years,
    required this.referenceMonth,
    required this.ownershipTargetMonth,
    required this.ownershipTargetAge,
    required this.ownershipTargetReached,
    required this.hasSavedPlannedExpenses,
    this.updatePending = false,
    this.onViewed,
  });

  final List<TimelineYearData> years;
  final YearMonth referenceMonth;
  final YearMonth ownershipTargetMonth;
  final int ownershipTargetAge;
  final bool ownershipTargetReached;
  final bool hasSavedPlannedExpenses;
  final bool updatePending;
  final VoidCallback? onViewed;

  // Display metadata only; yearly values and expense totals remain calculated data.
  YearMonth _evaluationMonth(int year) =>
      year == ownershipTargetMonth.year &&
          ownershipTargetMonth.compareTo(referenceMonth) >= 0
      ? ownershipTargetMonth
      : YearMonth(year, referenceMonth.month);

  @override
  Widget build(BuildContext context) => UpdateFeedback(
    pending: updatePending,
    duration: const Duration(milliseconds: 1600),
    onViewed: onViewed,
    builder: (context, emphasis) {
      final text = Theme.of(context).textTheme.apply(
        bodyColor: _RoadmapColors.text,
        displayColor: _RoadmapColors.text,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          // Give the route title its measured height even at large text scales.
          final titleStyle = text.headlineLarge!;
          final titlePainter = TextPainter(
            text: TextSpan(text: '未来タイムライン', style: titleStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth - 96);
          final toolbarHeight = titlePainter.height + AppSpacing.lg;
          titlePainter.dispose();
          return Scaffold(
            backgroundColor: _RoadmapColors.background,
            appBar: AppBar(
              backgroundColor: _RoadmapColors.background,
              foregroundColor: _RoadmapColors.text,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: toolbarHeight < kToolbarHeight
                  ? kToolbarHeight
                  : toolbarHeight,
              titleTextStyle: titleStyle,
              title: const Text(
                '未来タイムライン',
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenMargin,
                  vertical: AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('保有目標までの計画', style: text.headlineLarge),
                    const SizedBox(height: AppSpacing.xxl),
                    if (ownershipTargetReached) ...[
                      Semantics(
                        container: true,
                        excludeSemantics: true,
                        label:
                            '保有目標に到達しています。設定している保有目標、'
                            '$ownershipTargetAge歳、${formatMonth(ownershipTargetMonth)}',
                        child: Container(
                          key: const ValueKey('timeline-reached-target'),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: _RoadmapColors.target,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: _RoadmapColors.gold),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Icon(
                                  Icons.check_circle_outline,
                                  size: 28,
                                  color: _RoadmapColors.gold,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                '保有目標に到達しています',
                                style: text.titleLarge!.copyWith(
                                  color: _RoadmapColors.gold,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                '設定している保有目標：$ownershipTargetAge歳・${formatMonth(ownershipTargetMonth)}',
                                style: text.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (hasSavedPlannedExpenses) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '登録済みの予定費は削除されていません。「愛車予定費」から確認できます。',
                          style: text.bodyMedium!.copyWith(
                            color: _RoadmapColors.supporting,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                    ] else if (ownershipTargetMonth == referenceMonth) ...[
                      Text(
                        '今月が保有目標です',
                        style: text.titleLarge!.copyWith(
                          color: _RoadmapColors.gold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                    if (updatePending) ...[
                      Text(
                        '未来タイムラインを更新しました',
                        key: ValueKey('timeline-update-text'),
                        style: text.bodyLarge!.copyWith(
                          color: _RoadmapColors.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    for (final entry in years.indexed)
                      _TimelineYear(
                        isFirst: entry.$1 == 0,
                        isLast: entry.$1 == years.length - 1,
                        year: entry.$2.year,
                        ownerAge: entry.$2.ownerAge,
                        carAge: entry.$2.carAge,
                        mileageKm: entry.$2.mileageKm,
                        evaluationMonth: _evaluationMonth(entry.$2.year),
                        referenceMonth: referenceMonth,
                        expenses: entry.$2.expenses,
                        totalYen: entry.$2.totalYen,
                        emphasis: emphasis,
                        ownershipTargetAge: ownershipTargetAge,
                        ownershipTargetMonth:
                            !ownershipTargetReached &&
                                entry.$2.year == ownershipTargetMonth.year
                            ? ownershipTargetMonth
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _TimelineYear extends StatelessWidget {
  const _TimelineYear({
    required this.year,
    required this.isFirst,
    required this.isLast,
    required this.ownerAge,
    required this.carAge,
    required this.mileageKm,
    required this.evaluationMonth,
    required this.referenceMonth,
    required this.expenses,
    required this.totalYen,
    required this.emphasis,
    required this.ownershipTargetAge,
    required this.ownershipTargetMonth,
  });

  final int year;
  final bool isFirst;
  final bool isLast;
  final int ownerAge;
  final int carAge;
  final int mileageKm;
  final YearMonth evaluationMonth;
  final YearMonth referenceMonth;
  final List<PlannedExpense> expenses;
  final int totalYen;
  final double emphasis;
  final int ownershipTargetAge;
  final YearMonth? ownershipTargetMonth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.apply(
      bodyColor: _RoadmapColors.text,
      displayColor: _RoadmapColors.text,
    );
    final milestone = const {60, 65, 70, 75}.contains(ownerAge);
    final isCurrent = evaluationMonth == referenceMonth;
    final evaluationLabel =
        '${evaluationMonth.month}月時点${isCurrent ? '' : 'の見込み'}';
    final isTarget = ownershipTargetMonth != null;
    final nodeColor = isTarget
        ? _RoadmapColors.gold
        : isCurrent
        ? _RoadmapColors.accent
        : _RoadmapColors.node;
    final yearStyle = text.headlineLarge!.copyWith(height: 1.25);
    final stackedTotal = MediaQuery.textScalerOf(context).scale(28) > 42;
    final cardPadding = stackedTotal ? AppSpacing.sm : AppSpacing.lg;
    final cardBorderWidth = isTarget || isCurrent ? 1.5 : 1.0;
    final nodeCenter =
        cardPadding +
        cardBorderWidth +
        MediaQuery.textScalerOf(context).scale(yearStyle.fontSize!) * 1.25 / 2;
    return Stack(
      key: ValueKey('timeline-year-$year'),
      children: [
        if (!isFirst)
          Positioned(
            left: 12.5,
            top: 0,
            height: nodeCenter,
            child: Container(
              key: ValueKey('timeline-line-in-$year'),
              width: 3,
              color: _RoadmapColors.line,
            ),
          ),
        if (!isLast)
          Positioned(
            left: 12.5,
            top: nodeCenter,
            bottom: 0,
            child: Container(
              key: ValueKey('timeline-line-out-$year'),
              width: 3,
              color: _RoadmapColors.line,
            ),
          ),
        Positioned(
          left: 3,
          top: nodeCenter - 11,
          child: ExcludeSemantics(
            child: Container(
              key: ValueKey('timeline-dot-$year'),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nodeColor,
                border: Border.all(color: _RoadmapColors.background, width: 2),
              ),
              child: isTarget
                  ? const Icon(
                      Icons.flag,
                      size: 12,
                      color: _RoadmapColors.background,
                    )
                  : isCurrent
                  ? const Icon(
                      Icons.circle,
                      size: 8,
                      color: _RoadmapColors.background,
                    )
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxxl,
            bottom: AppSpacing.xxl,
          ),
          child: Container(
            key: ValueKey('timeline-card-$year'),
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_RoadmapColors.card, _RoadmapColors.cardEnd],
              ),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: isTarget
                    ? _RoadmapColors.gold
                    : isCurrent
                    ? _RoadmapColors.accent
                    : _RoadmapColors.border,
                width: cardBorderWidth,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  header: true,
                  excludeSemantics: true,
                  label: '$year年、$evaluationLabel${isCurrent ? '、現在' : ''}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: AppSpacing.md,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('$year年', style: yearStyle),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: _RoadmapColors.background,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                                border: Border.all(
                                  color: _RoadmapColors.accent,
                                ),
                              ),
                              child: Text(
                                '現在',
                                style: text.bodyMedium!.copyWith(
                                  color: _RoadmapColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        evaluationLabel,
                        style: text.bodyMedium!.copyWith(
                          color: _RoadmapColors.supporting,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  container: true,
                  excludeSemantics: true,
                  label:
                      'オーナー$ownerAge歳、車齢$carAge年、想定走行距離、約${formatNumber(mileageKm)}キロメートル',
                  child: Container(
                    key: ValueKey('timeline-emphasis-$year'),
                    color: _RoadmapColors.accent.withValues(
                      alpha: 0.10 * emphasis,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Text(
                              'オーナー $ownerAge歳',
                              style: text.bodyLarge!.copyWith(
                                fontWeight: milestone
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            Text('車齢 $carAge年', style: text.bodyLarge),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          '想定走行距離 約${formatKm(mileageKm)}',
                          style: text.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isTarget) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    container: true,
                    excludeSemantics: true,
                    label:
                        '保有目標、${formatMonth(ownershipTargetMonth!)}、'
                        '$ownershipTargetAge歳まで乗る計画',
                    child: Container(
                      key: ValueKey('timeline-target-$year'),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: _RoadmapColors.target,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        border: Border.all(color: _RoadmapColors.gold),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                size: 28,
                                color: _RoadmapColors.gold,
                              ),
                              Text(
                                ownershipTargetMonth == referenceMonth
                                    ? '保有目標：${formatMonth(ownershipTargetMonth!)}'
                                    : '保有目標',
                                style: text.titleMedium!.copyWith(
                                  color: _RoadmapColors.gold,
                                ),
                              ),
                            ],
                          ),
                          if (ownershipTargetMonth != referenceMonth)
                            Text(
                              formatMonth(ownershipTargetMonth!),
                              style: text.titleLarge!.copyWith(
                                color: _RoadmapColors.gold,
                              ),
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '$ownershipTargetAge歳まで乗る計画',
                            style: text.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  container: true,
                  excludeSemantics: true,
                  label: 'この年の予定費、${formatYen(totalYen)}',
                  child: Container(
                    key: ValueKey('timeline-total-$year'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: _RoadmapColors.border),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final amount = formatYen(totalYen);
                        var amountStyle = text.headlineLarge!.copyWith(
                          fontSize: 28,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        );
                        if (stackedTotal) {
                          final painter = TextPainter(
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                            locale: Localizations.maybeLocaleOf(context),
                          );
                          // Keep the user's scaler. Only adjust the base type
                          // size, never below body text; very long sums may wrap.
                          for (final size in [28.0, 24.0, 20.0, 18.0, 16.0]) {
                            amountStyle = amountStyle.copyWith(fontSize: size);
                            painter.text = TextSpan(
                              text: amount,
                              style: amountStyle,
                            );
                            painter.layout();
                            if (painter.width <= constraints.maxWidth - 1) {
                              break;
                            }
                          }
                          painter.dispose();
                        }
                        return Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: stackedTotal ? 'この年の予定費\n' : 'この年の予定費 ',
                                style: text.bodyMedium!.copyWith(
                                  color: _RoadmapColors.supporting,
                                ),
                              ),
                              TextSpan(text: amount, style: amountStyle),
                            ],
                          ),
                          style: text.titleMedium,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (expenses.isEmpty)
                  Text(
                    '予定費の登録はありません',
                    style: text.bodyMedium!.copyWith(
                      color: _RoadmapColors.supporting,
                    ),
                  )
                else
                  for (final expense in expenses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Semantics(
                        container: true,
                        excludeSemantics: true,
                        label:
                            '${expense.plannedMonth.month}月、${expense.name}、${formatYen(expense.amountYen)}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${expense.plannedMonth.month}月',
                              style: text.bodyMedium!.copyWith(
                                color: _RoadmapColors.supporting,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.md,
                              runSpacing: AppSpacing.xs,
                              children: [
                                Text(expense.name, style: text.titleMedium),
                                Text(
                                  formatYen(expense.amountYen),
                                  style: text.titleMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
