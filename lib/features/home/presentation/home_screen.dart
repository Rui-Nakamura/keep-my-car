import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/display_format.dart';
import '../../../app/plan_session.dart';
import '../../../app/save_request.dart';
import '../../../app/save_restriction.dart';
import '../../settings/presentation/funding_plan_screen.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../photo/photo_library.dart';
import 'home_car_photo.dart';
import '../../../domain/car_validation.dart';
import '../../../domain/models/car.dart';
import '../../../domain/models/plan_conditions.dart';
import '../../../domain/plan_conditions_validation.dart';
import '../../car/presentation/car_name_screen.dart';
import '../../planned_expenses/presentation/planned_expense_editor.dart';
import '../../planned_expenses/presentation/planned_expenses_screen.dart';
import '../../settings/presentation/plan_settings_screen.dart';
import '../../timeline/presentation/future_timeline_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.car,
    required this.onSaveCarName,
    required this.session,
    required this.onApply,
    required this.onNavigate,
    required this.onTimelineViewed,
    required this.onReserveViewed,
    required this.onExpensesChanged,
    required this.onSaveExpense,
    required this.onDeleteExpense,
    this.onDataManagement,
    this.onApplyFunding,
    this.photoId,
    this.photos,
  });
  final FutureOr<Map<PlanField, PlanInputError>> Function(PlanConditions)?
  onApplyFunding;
  final String? photoId;
  final PhotoLibrary? photos;
  final PlanSession session;
  final VoidCallback? onDataManagement;
  final Car car;
  final FutureOr<CarNameError?> Function(String) onSaveCarName;
  final FutureOr<Map<PlanField, PlanInputError>> Function(PlanConditions)
  onApply;
  final SaveExpenseRequest onSaveExpense;
  final DeleteExpenseRequest onDeleteExpense;
  final VoidCallback onNavigate;
  final VoidCallback onTimelineViewed;
  final VoidCallback onReserveViewed;
  final VoidCallback onExpensesChanged;

  Future<void> _editCarName(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CarNameScreen(name: car.name, onSave: onSaveCarName),
      ),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('愛車名を更新しました')));
    }
  }

  void _open(BuildContext context, Widget screen) {
    // Construct before the builder to fix this visit's feedback snapshot.
    onNavigate();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _settings(BuildContext context) => _open(
    context,
    PlanSettingsScreen(
      conditions: session.conditions,
      birthMonth: session.birthMonth,
      referenceMonth: session.referenceMonth,
      onApply: onApply,
      onDataManagement: onDataManagement,
      fundingStatusText: () => fundingStatusText(session.fundingPlanStatus),
      onFundingPlan: onApplyFunding == null ? null : () => _funding(context),
    ),
  );

  Future<void> _funding(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FundingPlanScreen(
          session: session,
          onApply: onApplyFunding!,
          onViewed: onReserveViewed,
        ),
      ),
    );
  }

  Future<void> _reviewTarget(BuildContext context) async {
    var applied = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlanSettingsScreen(
          conditions: session.conditions,
          birthMonth: session.birthMonth,
          referenceMonth: session.referenceMonth,
          onApply: (next) async {
            final errors = await onApply(next);
            if (errors.isEmpty) applied = true;
            return errors;
          },
          onDataManagement: onDataManagement,
          fundingStatusText: () => fundingStatusText(session.fundingPlanStatus),
          onFundingPlan: onApplyFunding == null
              ? null
              : () => _funding(context),
        ),
      ),
    );
    // Preserve newly generated HomeUpdate and pending flags on return.
    if (applied && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _expenses(BuildContext context) => _open(
    context,
    PlannedExpensesScreen(
      session: session,
      onChanged: onExpensesChanged,
      onReviewTarget: () => _reviewTarget(context),
      onSaveExpense: onSaveExpense,
      onDeleteExpense: onDeleteExpense,
    ),
  );

  Future<void> _addExpense(BuildContext context) async {
    if (session.ownershipTargetReached) return;
    onNavigate();
    final change = await Navigator.of(context).push<ExpenseChange>(
      MaterialPageRoute<ExpenseChange>(
        builder: (_) => PlannedExpenseEditor(
          session: session,
          onSave: onSaveExpense,
          onDelete: onDeleteExpense,
        ),
      ),
    );
    if (!context.mounted || change != ExpenseChange.added) return;
    // Suppress this operation's Home text only; preserve screen pending flags.
    session.consumeHomeUpdate();
    onExpensesChanged();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('予定費を追加しました')));
  }

  String _remainingPeriod() {
    final months = session.monthsUntilOwnershipTarget;
    if (months == 0) return '今月が保有目標です';
    final years = months ~/ 12;
    final remainder = months % 12;
    return 'あと${years > 0 ? '$years年' : ''}${remainder > 0 ? '$remainderか月' : ''}';
  }

  void _timeline(BuildContext context) => _open(
    context,
    FutureTimelineScreen(
      years: session.timeline,
      fundingTargetMonth:
          session.fundingPlanStatus == FundingPlanStatus.calculable
          ? reserveMonth(
              session.birthMonth,
              session.conditions.reserveTargetAge,
            )
          : null,
      fundingTargetAge: session.conditions.reserveTargetAge,
      fundingTargetYen: session.conditions.largeRepairReserveYen,
      referenceMonth: session.referenceMonth,
      ownershipTargetMonth: session.ownershipTargetMonth,
      ownershipTargetAge: session.conditions.ownershipTargetAge,
      ownershipTargetReached: session.ownershipTargetReached,
      hasSavedPlannedExpenses: session.plannedExpenses.isNotEmpty,
      updatePending: session.timelinePending,
      onViewed: onTimelineViewed,
      onReviewTarget: () => _reviewTarget(context),
    ),
  );

  Widget _menu(BuildContext context) => PopupMenuButton<_HomeAction>(
    key: const ValueKey('home-menu'),
    tooltip: 'メニュー',
    icon: const Icon(Icons.menu, color: AppColors.primary),
    onSelected: (action) {
      switch (action) {
        case _HomeAction.photo:
          break; // Reserved, disabled until F-Impl-06.
        case _HomeAction.name:
          _editCarName(context);
        case _HomeAction.plan:
          _settings(context);
        case _HomeAction.data:
          onNavigate();
          onDataManagement?.call();
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: _HomeAction.photo,
        enabled: false,
        child: Text('愛車の写真'),
      ),
      PopupMenuItem(
        value: _HomeAction.name,
        enabled: !SaveRestriction.of(context),
        child: const Text('愛車名を編集'),
      ),
      const PopupMenuItem(value: _HomeAction.plan, child: Text('愛車の計画を見直す')),
      PopupMenuItem(
        value: _HomeAction.data,
        enabled: onDataManagement != null,
        child: const Text('データ管理'),
      ),
    ],
  );

  Widget _header(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    final brand = Column(
      children: [
        const Icon(
          Icons.directions_car_outlined,
          color: AppColors.primary,
          size: 28,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Keep My Car',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge!.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) => Text(
            _homePhraseLines(
              context,
              const ['好きな車に、', 'あと何年', '乗れる？'],
              Theme.of(context).textTheme.bodyMedium!,
              constraints.maxWidth,
            ),
            semanticsLabel: '好きな車に、あと何年乗れる？',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (largeText) ...[
          Align(alignment: Alignment.centerRight, child: _menu(context)),
          brand,
        ] else
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Center(child: brand),
              ),
              Align(alignment: Alignment.topRight, child: _menu(context)),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          car.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _target(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal =
          constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(16) <= 20;
      final information = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HomeLabel(icon: Icons.outlined_flag, label: 'あなたの保有目標'),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: '${session.ownershipTargetOwnerAge}歳まで乗る計画',
              excludeSemantics: true,
              child: _HomeNumber(
                value: '${session.ownershipTargetOwnerAge}',
                unit: '歳',
                fontSize: 80,
                unitScale: 0.44,
                textKey: const ValueKey('home-target-age'),
              ),
            ),
            Text(
              '${formatMonth(session.ownershipTargetMonth)}まで',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              _remainingPeriod(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1),
            ),
            _HomeAdaptiveRow(
              horizontal: horizontal,
              flexes: const [1, 2],
              children: [
                _HomeMetric(
                  icon: Icons.directions_car_outlined,
                  label: '車齢',
                  value: '${session.ownershipTargetCarAge}',
                  unit: '年',
                ),
                _HomeMetric(
                  icon: Icons.speed,
                  label: '予想走行距離',
                  value: formatNumber(session.ownershipTargetMileageKm),
                  unit: 'km',
                ),
              ],
            ),
          ],
        ),
      );
      final photo = HomeCarPhoto(photoId: photoId, library: photos);
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ColoredBox(
          color: AppColors.surface,
          child: horizontal
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: 4 / 11,
                          child: photo,
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 7 / 11,
                      child: information,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    information,
                    SizedBox(height: 180, child: photo),
                  ],
                ),
        ),
      );
    },
  );

  Widget _expenseSummary(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final next = session.expensesInNextMonth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeLabel(
          icon: Icons.savings_outlined,
          label: 'これから必要な予定費',
          style: text.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _homeMint,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) => _HomeAdaptiveRow(
                horizontal:
                    constraints.maxWidth >= 280 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 20,
                flexes: const [3, 2],
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('保有目標までの合計', style: text.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      _HomeNumber(
                        value: formatNumber(
                          session.ownershipTargetExpensesTotalYen,
                        ),
                        unit: '円',
                        fontSize: 32,
                        textKey: const ValueKey('home-expense-total'),
                      ),
                    ],
                  ),
                  Text(
                    [
                      _homePhraseLines(
                        context,
                        ['${formatMonth(session.ownershipTargetMonth)}まで'],
                        text.bodyMedium!,
                        constraints.maxWidth,
                      ),
                      _homePhraseLines(
                        context,
                        const ['登録している', '予定費の', '合計です'],
                        text.bodyMedium!,
                        constraints.maxWidth >= 280 &&
                                MediaQuery.textScalerOf(context).scale(16) <= 20
                            ? (constraints.maxWidth - AppSpacing.sm) * 2 / 5
                            : constraints.maxWidth,
                      ),
                    ].join('\n'),
                    semanticsLabel:
                        '${formatMonth(session.ownershipTargetMonth)}まで。登録している予定費の合計です',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = _expenseColumnsFit(
              context,
              constraints.maxWidth,
            );
            final stackedLabel =
                horizontal &&
                _homeTextWidth(context, '今後5年間', text.bodyMedium!) + 22 >
                    (constraints.maxWidth - AppSpacing.sm * 2) / 3 -
                        AppSpacing.sm * 2;
            final amountWidth =
                (horizontal
                    ? (constraints.maxWidth - AppSpacing.sm * 2) / 3
                    : constraints.maxWidth) -
                AppSpacing.sm * 2;
            return _HomeAdaptiveRow(
              horizontal: horizontal,
              equalHeight: true,
              children: [
                _HomeExpenseSummary(
                  icon: Icons.event_outlined,
                  title: '次の予定費',
                  amountWidth: amountWidth,
                  stackedLabel: stackedLabel,
                  wide: !horizontal,
                  amount: session.nextMonthTotalYen,
                  detail:
                      '${formatMonth(session.nextExpenseMonth!)}\n${next.first.name}${next.length > 1 ? ' ほか${next.length - 1}件' : ''}',
                  onTap: () => _expenses(context),
                ),
                _HomeExpenseSummary(
                  icon: Icons.calendar_month_outlined,
                  title: '来年',
                  amountWidth: amountWidth,
                  stackedLabel: stackedLabel,
                  wide: !horizontal,
                  amount: session.nextYearExpensesTotalYen,
                  detail: '${session.referenceMonth.year + 1}年の予定費',
                  detailParts: [
                    ['${session.referenceMonth.year + 1}年', 'の予定費'],
                  ],
                  onTap: () => _expenses(context),
                ),
                _HomeExpenseSummary(
                  icon: Icons.bar_chart,
                  title: '今後5年間',
                  amountWidth: amountWidth,
                  stackedLabel: stackedLabel,
                  wide: !horizontal,
                  amount: session.fiveYearExpensesTotalYen,
                  detail:
                      '${session.referenceMonth.year}年〜${session.referenceMonth.year + 4}年の予定費の合計',
                  detailParts: [
                    [
                      '${session.referenceMonth.year}年〜',
                      '${session.referenceMonth.year + 4}年',
                      'の予定費',
                      'の合計',
                    ],
                  ],
                  onTap: () => _expenses(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  bool _expenseColumnsFit(BuildContext context, double width) {
    if (width < 300) {
      return false;
    }
    final available = (width - AppSpacing.sm * 2) / 3 - AppSpacing.sm * 2;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    try {
      for (final title in ['次の予定費', '来年', '今後5年間']) {
        painter.text = TextSpan(
          text: title,
          style: Theme.of(context).textTheme.bodyMedium,
        );
        painter.layout();
        if (painter.width > available) return false;
      }
      for (final amount in [
        session.nextMonthTotalYen,
        session.nextYearExpensesTotalYen,
        session.fiveYearExpensesTotalYen,
      ]) {
        painter.text = TextSpan(
          text: formatYen(amount),
          style: Theme.of(context).textTheme.labelLarge,
        );
        painter.layout();
        if (painter.width > available) return false;
      }
      return true;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reached = session.ownershipTargetReached;
    final notice = switch (session.homeUpdate) {
      HomeUpdate.timeline || HomeUpdate.both => '未来タイムラインを更新しました',
      HomeUpdate.reserve || null => null,
    };
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.lg,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  const SizedBox(height: AppSpacing.xl),
                  if (reached) ...[
                    Text('保有目標に到達しています', style: text.displayMedium),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '設定していた保有目標は ${formatMonth(session.ownershipTargetMonth)}でした',
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'これからも乗り続ける場合は、新しい保有目標を設定してください。',
                      style: text.bodyLarge,
                    ),
                    OutlinedButton(
                      onPressed: () => _settings(context),
                      child: const Text('保有目標を見直す'),
                    ),
                    if (session.plannedExpenses.isNotEmpty)
                      TextButton(
                        onPressed: () => _expenses(context),
                        child: const Text('予定費を確認する'),
                      ),
                  ] else ...[
                    _target(context),
                    const SizedBox(height: AppSpacing.xl),
                    if (session.includedExpenses.isNotEmpty)
                      _expenseSummary(context)
                    else if (session.plannedExpenses.isEmpty) ...[
                      Text('予定費はまだありません', style: text.titleLarge),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '車検やタイヤ交換など、これから予定している費用を登録すると、保有目標までのお金の見通しを確認できます。',
                        style: text.bodyLarge,
                      ),
                    ] else ...[
                      Text('保有目標までの予定費はありません', style: text.titleLarge),
                      TextButton(
                        onPressed: () => _expenses(context),
                        child: const Text('予定費を確認する'),
                      ),
                    ],
                  ],
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        notice,
                        key: const ValueKey('home-update'),
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                  if (!reached) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: SaveRestriction.of(context)
                          ? null
                          : () => _addExpense(context),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const label = '＋ 予定費を追加する';
                          final style = text.labelLarge!;
                          final fits =
                              _homeTextWidth(context, label, style) <=
                              constraints.maxWidth;
                          return Semantics(
                            label: label,
                            excludeSemantics: true,
                            child: fits
                                ? const Text(label)
                                : Row(
                                    children: [
                                      const Icon(
                                        Icons.add_circle_outline,
                                        size: 24,
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Text(
                                          _homePhraseLines(
                                            context,
                                            const ['予定費を', '追加する'],
                                            style,
                                            constraints.maxWidth - 36,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columnWidth =
                          (constraints.maxWidth - AppSpacing.sm * 2) / 3;
                      final horizontal = const ['タイムライン', '愛車予定費', '愛車の計画を']
                          .every(
                            (part) =>
                                _homeTextWidth(
                                  context,
                                  part,
                                  text.bodyMedium!.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ) <=
                                columnWidth - AppSpacing.sm,
                          );
                      final labelWidth = (horizontal
                          ? columnWidth - AppSpacing.sm
                          : constraints.maxWidth - AppSpacing.sm * 2);
                      return _HomeAdaptiveRow(
                        equalHeight: true,
                        horizontal: horizontal,
                        children: [
                          _HomeLink(
                            icon: Icons.schedule,
                            label: '未来タイムラインを見る',
                            parts: const ['未来', 'タイムライン', 'を見る'],
                            width: labelWidth,
                            wide: !horizontal,
                            onTap: () => _timeline(context),
                          ),
                          _HomeLink(
                            icon: Icons.build_outlined,
                            label: '愛車予定費を見る',
                            parts: const ['愛車予定費', 'を見る'],
                            width: labelWidth,
                            wide: !horizontal,
                            onTap: () => _expenses(context),
                          ),
                          _HomeLink(
                            icon: Icons.article_outlined,
                            label: '愛車の計画を見直す',
                            parts: const ['愛車の計画を', '見直す'],
                            width: labelWidth,
                            wide: !horizontal,
                            onTap: () => _settings(context),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _HomeAction { photo, name, plan, data }

const _homeMint = Color(0xFFE9F3EF);

class _HomeLabel extends StatelessWidget {
  const _HomeLabel({required this.icon, required this.label, this.style});
  final IconData icon;
  final String label;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          label,
          style: style ?? Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

/// Keep each number whole. Measure using the actual system TextScaler rather
/// than clamping accessibility settings or dropping digits with ellipsis.
class _HomeNumber extends StatelessWidget {
  const _HomeNumber({
    required this.value,
    required this.unit,
    required this.fontSize,
    this.unitScale = 0.65,
    this.textKey,
    this.availableWidth,
  });
  final String value;
  final String unit;
  final double fontSize;
  final double unitScale;
  final Key? textKey;
  final double? availableWidth;

  Widget _text(BuildContext context, double width) {
    final base = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    TextSpan span(double size) => TextSpan(
      style: base.copyWith(fontSize: size),
      children: [
        TextSpan(text: value),
        TextSpan(
          text: unit,
          style: TextStyle(fontSize: size * unitScale),
        ),
      ],
    );
    var size = fontSize;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      painter.text = span(size);
      painter.layout();
      if (painter.width <= width) break;
      size *= width / painter.width * 0.99;
    }
    painter.dispose();
    return Text.rich(span(size), key: textKey, softWrap: false);
  }

  @override
  Widget build(BuildContext context) => availableWidth != null
      ? _text(context, availableWidth!)
      : LayoutBuilder(
          builder: (context, constraints) =>
              _text(context, constraints.maxWidth),
        );
}

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _HomeLabel(icon: icon, label: label),
      const SizedBox(height: AppSpacing.xs),
      _HomeNumber(value: value, unit: unit, fontSize: 24),
    ],
  );
}

class _HomeAdaptiveRow extends StatelessWidget {
  const _HomeAdaptiveRow({
    required this.horizontal,
    required this.children,
    this.flexes,
    this.equalHeight = false,
  });
  final bool horizontal;
  final List<Widget> children;
  final List<int>? flexes;
  final bool equalHeight;
  @override
  Widget build(BuildContext context) {
    if (!horizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            children[i],
          ],
        ],
      );
    }
    final row = Row(
      crossAxisAlignment: equalHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(flex: flexes?[i] ?? 1, child: children[i]),
        ],
      ],
    );
    return equalHeight ? IntrinsicHeight(child: row) : row;
  }
}

class _HomeExpenseSummary extends StatelessWidget {
  const _HomeExpenseSummary({
    required this.icon,
    required this.title,
    required this.amount,
    required this.amountWidth,
    required this.detail,
    required this.onTap,
    required this.stackedLabel,
    required this.wide,
    this.detailParts,
  });
  final IconData icon;
  final String title;
  final int amount;
  final double amountWidth;
  final String detail;
  final List<List<String>>? detailParts;
  final VoidCallback onTap;
  final bool stackedLabel;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      key: ValueKey('home-summary-$title'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.buttonMinHeight,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: wide ? AppSpacing.md : AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stackedLabel) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(icon, size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    title,
                    style: text.bodyMedium!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ] else
                  _HomeLabel(
                    icon: icon,
                    label: title,
                    style: text.bodyMedium!.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _HomeNumber(
                  value: formatNumber(amount),
                  unit: '円',
                  fontSize: 20,
                  availableWidth: amountWidth,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final parts
                    in detailParts ??
                        detail.split('\n').map((line) => [line]).toList())
                  Text(
                    _homePhraseLines(
                      context,
                      parts,
                      text.bodyMedium!,
                      amountWidth,
                    ),
                    semanticsLabel: parts.join(),
                    style: text.bodyMedium,
                  ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeLink extends StatelessWidget {
  const _HomeLink({
    required this.icon,
    required this.label,
    required this.parts,
    required this.width,
    required this.wide,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final List<String> parts;
  final double width;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontWeight: FontWeight.w600);
    final inline =
        wide &&
        parts.every(
          (part) => _homeTextWidth(context, part, style) <= width - 46,
        );
    final labelWidget = Semantics(
      label: label,
      excludeSemantics: true,
      child: Text(
        _homePhraseLines(context, parts, style, inline ? width - 46 : width),
        textAlign: wide ? TextAlign.start : TextAlign.center,
        style: style,
      ),
    );
    final leading = Icon(icon, color: AppColors.accent, size: wide ? 18 : 24);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 64),
        padding: EdgeInsets.symmetric(
          horizontal: wide ? AppSpacing.sm : AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      child: inline
          ? Row(
              children: [
                leading,
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: labelWidget),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right, size: 16),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      leading,
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  )
                else
                  Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: _homeMint,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: leading,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                labelWidget,
                if (!wide) const Icon(Icons.chevron_right, size: 18),
              ],
            ),
    );
  }
}

// These are display-only line breaks for the few known Home phrases. Long
// user-entered text still wraps normally; text scaling and source values remain
// untouched. Passing the known width also keeps the compact intrinsic rows safe.
double _homeTextWidth(BuildContext context, String value, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

String _homePhraseLines(
  BuildContext context,
  List<String> parts,
  TextStyle style,
  double width,
) {
  final lines = <String>[];
  var line = '';
  for (final part in parts) {
    if (line.isNotEmpty &&
        _homeTextWidth(context, line + part, style) > width) {
      lines.add(line);
      line = part.trimLeft();
    } else {
      line += part;
    }
  }
  lines.add(line);
  return lines.join('\n');
}
