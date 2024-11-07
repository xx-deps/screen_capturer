import 'dart:typed_data';
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

class CapturedDisplay extends Display {
  CapturedDisplay({
    required super.id,
    required super.size,
    required this.imagePath,
    super.name,
    super.visiblePosition,
    super.visibleSize,
    super.scaleFactor,
    super.handle,
  });

  /// Creates a [CapturedDisplay] from an existing [Display] and an image path
  factory CapturedDisplay.fromDisplay(Display display, String imagePath) {
    return CapturedDisplay(
      id: display.id,
      size: display.size,
      imagePath: imagePath,
      name: display.name,
      visiblePosition: display.visiblePosition,
      visibleSize: display.visibleSize,
      scaleFactor: display.scaleFactor,
      handle: display.handle,
    );
  }

  final String imagePath;
}
