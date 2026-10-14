import 'package:flutter/material.dart';

/// Live UI permission; persistence boundaries remain the final authority.
class SaveRestriction extends InheritedWidget {
  const SaveRestriction({
    super.key,
    required this.restricted,
    required super.child,
  });
  final bool restricted;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SaveRestriction>()
          ?.restricted ??
      false;
  @override
  bool updateShouldNotify(SaveRestriction oldWidget) =>
      restricted != oldWidget.restricted;
}

const saveRestrictionMessage =
    'データを守るため、変更を保存できません。アプリを更新してください。現在のデータは閲覧できます。';
