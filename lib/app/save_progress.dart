import 'package:flutter/material.dart';

/// Prevents edits and navigation while the screen awaits its save callback.
class SaveProgress extends StatelessWidget {
  const SaveProgress({super.key, required this.saving, required this.child});
  final bool saving;
  final Widget child;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AbsorbPointer(absorbing: saving, child: child),
  );
}
