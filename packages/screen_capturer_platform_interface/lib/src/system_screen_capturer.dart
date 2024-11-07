import 'package:screen_retriever/screen_retriever.dart';
abstract mixin class SystemScreenCapturer {
  Future<List<Display>> captureInMultiMonitor({
    required String imagePath,
  });
}
