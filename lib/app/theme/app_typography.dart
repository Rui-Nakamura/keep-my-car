import 'package:flutter/material.dart';

abstract final class AppTypography {
  // No fontFamily override: retain Flutter's platform typography.
  static const hero = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w600,
    height: 1.20,
  );
  static const mainAmount = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.20,
  );
  static const pageTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w600);
  static const sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const supporting = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  static const textTheme = TextTheme(
    displayLarge: hero,
    displayMedium: mainAmount,
    displaySmall: pageTitle,
    headlineLarge: pageTitle,
    headlineMedium: sectionTitle,
    headlineSmall: sectionTitle,
    titleLarge: sectionTitle,
    titleMedium: label,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: supporting,
    bodySmall: supporting,
    labelLarge: label,
    labelMedium: label,
    labelSmall: label,
  );
}
