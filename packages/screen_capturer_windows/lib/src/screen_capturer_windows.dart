import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';
import 'package:screen_capturer_windows/src/commands/custom_screen_capture.dart';

class ScreenCapturerWindows extends MethodChannelScreenCapturer {
  /// The [ScreenCapturerWindows] constructor.
  ScreenCapturerWindows() : super();

  /// Registers this class as the default instance of [ScreenCapturerWindows].
  static void registerWith() {
    ScreenCapturerPlatform.instance = ScreenCapturerWindows();
  }

  @override
  SystemScreenCapturer get systemScreenCapturer => CustomScreenCapture();
}
