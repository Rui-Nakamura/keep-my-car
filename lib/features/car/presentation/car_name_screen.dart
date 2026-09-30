import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/save_request.dart';
import '../../../app/save_progress.dart';

import 'package:flutter/services.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../domain/car_validation.dart';

class CarNameScreen extends StatefulWidget {
  const CarNameScreen({super.key, required this.name, required this.onSave});

  final String name;
  final FutureOr<CarNameError?> Function(String) onSave;

  @override
  State<CarNameScreen> createState() => _CarNameScreenState();
}

class _CarNameScreenState extends State<CarNameScreen> {
  late final TextEditingController _controller;
  CarNameError? _error;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  Future<void> _save() async {
    if (_saving) return;
    final result = validateCarName(_controller.text);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final error = result.error ?? await widget.onSave(result.name);
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      Navigator.of(context).pop(result.name != widget.name);
    } on SaveRequestFailure catch (error) {
      if (mounted && !error.uncertain) {
        setState(() => _saveError = SaveRequestFailure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SaveProgress(
    saving: _saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('愛車名を編集')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenMargin,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('愛車表示名', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                label: '愛車表示名',
                child: TextField(
                  key: const ValueKey('car-name-input'),
                  controller: _controller,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[\r\n\t]')),
                  ],
                  scrollPadding: const EdgeInsets.all(32),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('40文字以内で入力してください'),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  switch (_error!) {
                    CarNameError.required => '愛車表示名を入力してください',
                    CarNameError.tooLong => '愛車表示名は40文字以内で入力してください',
                    CarNameError.invalidCharacters => '愛車表示名に改行やタブは使用できません',
                  },
                  key: const ValueKey('car-name-error'),
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (_saveError != null)
                Text(_saveError!, key: const ValueKey('save-error')),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
