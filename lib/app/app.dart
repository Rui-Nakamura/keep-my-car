import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class KeepMyCarApp extends StatelessWidget {
  const KeepMyCarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keep My Car',
    theme: AppTheme.light,
    themeMode: ThemeMode.light,
    home: const Scaffold(body: Center(child: Text('Keep My Car'))),
  );
}
