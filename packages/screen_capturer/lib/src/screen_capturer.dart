import 'dart:io';
import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';

class ScreenCapturer {
  ScreenCapturer._();

  /// The shared instance of [ScreenCapturer].
  static final ScreenCapturer instance = ScreenCapturer._();

  ScreenCapturerPlatform get _platform => ScreenCapturerPlatform.instance;

  /// Captures the screen and saves it to the specified [imagePath]
  ///
  /// Returns a [CapturedData] object with the image path, width, height and base64 encoded image
  Future<List<CapturedDisplay>> captureInMultiMonitor({
    required String imagePath,
  }) async {
    File imageFile =  File(imagePath);

    if (!imageFile.parent.existsSync()) {
      imageFile.parent.create(recursive: true);
    }

    final capturedDisplays = await _platform.systemScreenCapturer.captureInMultiMonitor(
      imagePath: imagePath,
    );
    return capturedDisplays;
  }
}
