import 'dart:typed_data';
import 'dart:ui';
import 'package:screen_retriever/screen_retriever.dart';

class CapturedData {
  CapturedData({
    this.imageWidth,
    this.imageHeight,
    this.imageBytes,
    this.imagePath,
  });

  final int? imageWidth;
  final int? imageHeight;
  final Uint8List? imageBytes;
  final String? imagePath;
}

class CapturedDisplay {
  CapturedDisplay({
    required this.display,
    required this.imagePath,
    required this.windows,
  });
  final Display display;
  final String imagePath;
  final List<WindowInfo> windows;
}

class WindowInfo {
  WindowInfo({
    required this.handle,
    required this.title,
    required this.bounds,
    required this.displayId,
  });
  final int handle;
  final String title;
  final Rect bounds;
  final String displayId;
}
