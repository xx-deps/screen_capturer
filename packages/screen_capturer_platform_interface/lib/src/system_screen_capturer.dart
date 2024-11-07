import 'package:screen_capturer_platform_interface/src/captured_data.dart';

abstract mixin class SystemScreenCapturer {
  Future<List<CapturedDisplay>> captureInMultiMonitor({
    required String imagePath,
  });
}
