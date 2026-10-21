import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'photo/photo_library.dart';

void main() =>
    runApp(KeepMyCarApp(photos: PhotoLibrary.backupApplicationSupport()));
