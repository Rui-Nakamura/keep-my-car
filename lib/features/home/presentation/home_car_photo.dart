import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../photo/photo_library.dart';

/// Reads only the formal photo reference. Selection and persistence belong to
/// the photo settings flow, not to this display widget.
class HomeCarPhoto extends StatefulWidget {
  const HomeCarPhoto({super.key, required this.photoId, required this.library});

  final String? photoId;
  final PhotoLibrary? library;

  @override
  State<HomeCarPhoto> createState() => _HomeCarPhotoState();
}

class _HomeCarPhotoState extends State<HomeCarPhoto> {
  Future<Uint8List?>? _photo;
  bool _reportedError = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(HomeCarPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoId != widget.photoId ||
        !identical(oldWidget.library, widget.library)) {
      _read();
    }
  }

  void _read() {
    _reportedError = false;
    final id = widget.photoId;
    final library = widget.library;
    _photo = id == null || library == null ? null : library.read(id);
  }

  Widget _placeholder(String label, String state) => Semantics(
    label: label,
    image: true,
    child: ColoredBox(
      key: ValueKey('home-photo-$state'),
      color: AppColors.surfaceSubtle,
      child: const Center(
        child: Icon(
          Icons.directions_car_outlined,
          size: 56,
          color: AppColors.textTertiary,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_photo == null) {
      return _placeholder(
        widget.photoId == null ? '愛車の写真は未設定です' : '愛車の写真を表示できません',
        widget.photoId == null ? 'unset' : 'unavailable',
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        // A replacement Future may retain the previous data while waiting.
        // Never show it under the new formal photo reference.
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder('愛車の写真を読み込んでいます', 'loading');
        }
        if (snapshot.hasError) {
          // read() already handles expected file/image failures. Unexpected
          // errors remain observable through Flutter's diagnostic contract.
          if (!_reportedError) {
            _reportedError = true;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: snapshot.error!,
                stack: snapshot.stackTrace,
                library: 'Keep My Car Home photo',
                context: ErrorDescription('while reading the formal car photo'),
              ),
            );
          }
          return _placeholder('愛車の写真を読み込めませんでした', 'error');
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return _placeholder('愛車の写真を表示できません', 'unavailable');
        }
        return Image.memory(
          bytes,
          key: const ValueKey('home-photo-image'),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: false,
          semanticLabel: '愛車の写真',
          errorBuilder: (context, error, stackTrace) =>
              _placeholder('愛車の写真を表示できません', 'decode-error'),
        );
      },
    );
  }
}
