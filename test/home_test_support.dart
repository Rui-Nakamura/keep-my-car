import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Use the same Japanese font as the Home widget captures, rather than Ahem's
/// square glyphs. Other hosts can provide an installed Japanese font explicitly;
/// a missing font fails the layout tests instead of silently skipping them.
Future<void> loadHomeJapaneseFont() async {
  final path =
      Platform.environment['KMC_JAPANESE_TEST_FONT'] ??
      r'C:\Windows\Fonts\YuGothM.ttc';
  final font = File(path);
  if (!await font.exists()) {
    throw StateError(
      'Home layout tests require a Japanese font. '
      'Set KMC_JAPANESE_TEST_FONT to its local path (missing: $path).',
    );
  }
  final loader = FontLoader('Roboto')
    ..addFont(font.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

/// Action labels can have presentation-only line breaks. Match the unchanged
/// accessible name, independently of their visual line layout.
Finder homeActionLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder homeControl(String label) =>
    const ['＋ 予定費を追加する', '未来タイムラインを見る', '愛車予定費を見る', '愛車の計画を見直す'].contains(label)
    ? homeActionLabel(label)
    : find.text(label);

Future<void> openHomeMenu(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('home-menu'));
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

Future<void> tapHomeMenuItem(WidgetTester tester, String label) async {
  await openHomeMenu(tester);
  final item = find.text(label).last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}
