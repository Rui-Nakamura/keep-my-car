import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  // Explicit roles: no seeded or system-derived brand colors.
  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.surfaceSubtle,
    onPrimaryContainer: AppColors.primary,
    primaryFixed: AppColors.surfaceSubtle,
    primaryFixedDim: AppColors.border,
    onPrimaryFixed: AppColors.primary,
    onPrimaryFixedVariant: AppColors.textSecondary,
    secondary: AppColors.accent,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.surfaceSubtle,
    onSecondaryContainer: AppColors.accent,
    secondaryFixed: AppColors.surfaceSubtle,
    secondaryFixedDim: AppColors.border,
    onSecondaryFixed: AppColors.accent,
    onSecondaryFixedVariant: AppColors.textSecondary,
    tertiary: AppColors.accent,
    onTertiary: AppColors.onPrimary,
    tertiaryContainer: AppColors.surfaceSubtle,
    onTertiaryContainer: AppColors.accent,
    tertiaryFixed: AppColors.surfaceSubtle,
    tertiaryFixedDim: AppColors.border,
    onTertiaryFixed: AppColors.accent,
    onTertiaryFixedVariant: AppColors.textSecondary,
    error: AppColors.error,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.errorBackground,
    onErrorContainer: AppColors.error,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceDim: AppColors.surfaceSubtle,
    surfaceBright: AppColors.surface,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: AppColors.surfaceSubtle,
    surfaceContainerHigh: AppColors.surfaceSubtle,
    surfaceContainerHighest: AppColors.surfaceSubtle,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.surface,
    inversePrimary: AppColors.surface,
    shadow: AppColors.textPrimary,
    scrim: AppColors.textPrimary,
    surfaceTint: AppColors.surface,
  );

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final textTheme = base.textTheme
        .merge(AppTypography.textTheme)
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      disabledColor: AppColors.textDisabled,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.merge(AppTypography.textTheme),
      iconTheme: const IconThemeData(
        size: AppSizes.icon,
        color: AppColors.textSecondary,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.headlineLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(
            color: AppColors.divider,
            width: AppSizes.borderWidth,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: AppSizes.borderWidth,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizes.buttonMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceSubtle,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.buttonMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textDisabled,
          side: const BorderSide(
            color: AppColors.buttonBorder,
            width: AppSizes.borderWidth,
          ),
          textStyle: textTheme.labelLarge,
          shape: buttonShape,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        constraints: const BoxConstraints(minHeight: AppSizes.inputMinHeight),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(AppSpacing.lg),
        labelStyle: textTheme.bodyMedium!.copyWith(
          color: AppColors.textSecondary,
        ),
        // InputDecorator scales floating labels by 0.75. Compensate so the
        // rendered label remains >= 14sp, including at larger text scales.
        floatingLabelStyle: textTheme.bodyMedium!.copyWith(
          fontSize: AppTypography.supporting.fontSize! / 0.75,
          color: AppColors.textSecondary,
        ),
        hintStyle: textTheme.bodyLarge!.copyWith(color: AppColors.textTertiary),
        helperStyle: textTheme.bodyMedium!.copyWith(
          color: AppColors.textSecondary,
        ),
        errorStyle: textTheme.bodyMedium!.copyWith(color: AppColors.error),
        counterStyle: textTheme.bodyMedium!.copyWith(
          color: AppColors.textSecondary,
        ),
        border: _inputBorder(AppColors.inputBorder),
        enabledBorder: _inputBorder(AppColors.inputBorder),
        disabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.accent),
        errorBorder: _inputBorder(AppColors.error),
        focusedErrorBorder: _inputBorder(AppColors.error),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.bottomSheet),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        labelStyle: textTheme.labelLarge,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.input),
    borderSide: BorderSide(color: color, width: AppSizes.borderWidth),
  );
}
