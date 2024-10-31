import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';

Future<Rect?> showScreenshotOverlay(
  BuildContext context,
  ui.Image screenImage, {
  required CaptureMode mode,
}) {
  return showDialog<Rect>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    builder: (context) => ScreenshotOverlay(
      screenImage: screenImage,
      mode: mode,
    ),
  );
}

class ScreenshotOverlay extends StatefulWidget {

  const ScreenshotOverlay({
    super.key,
    required this.screenImage,
    required this.mode,
  });
  
  final ui.Image screenImage;
  final CaptureMode mode;

  @override
  State<ScreenshotOverlay> createState() => _ScreenshotOverlayState();
}

class _ScreenshotOverlayState extends State<ScreenshotOverlay> {
  Offset? _start;
  Offset? _current;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景截图
        Positioned.fill(
          child: RawImage(
            image: widget.screenImage,
            fit: BoxFit.fill,
          ),
        ),
        // 半透明遮罩
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.3),
          ),
        ),
        // 选择区域
        if (_start != null && _current != null)
          CustomPaint(
            size: Size.infinite,
            painter: SelectionPainter(
              start: _start!,
              current: _current!,
            ),
          ),
        // 手势检测
        Positioned.fill(
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _start = details.localPosition;
                _current = details.localPosition;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _current = details.localPosition;
              });
            },
            onPanEnd: (details) {
              if (_start != null && _current != null) {
                final rect = Rect.fromPoints(_start!, _current!);
                Navigator.of(context).pop(rect);
              }
            },
          ),
        ),
      ],
    );
  }
}

class SelectionPainter extends CustomPainter {

  SelectionPainter({
    required this.start,
    required this.current,
  });

  final Offset start;
  final Offset current;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, current);
    
    // 清除选择区域的遮罩
    canvas.drawRect(
      rect,
      Paint()..blendMode = BlendMode.clear,
    );
    
    // 绘制选择框边框
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    
    // 绘制四角标记
    _drawCornerMarks(canvas, rect);
  }

  void _drawCornerMarks(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const markerLength = 10.0;

    // 左上角
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft.translate(markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft.translate(0, markerLength),
      paint,
    );

    // 右上角
    canvas.drawLine(
      rect.topRight,
      rect.topRight.translate(-markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight.translate(0, markerLength),
      paint,
    );

    // 左下角
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(0, -markerLength),
      paint,
    );

    // 右下角
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(-markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(0, -markerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(SelectionPainter oldDelegate) {
    return start != oldDelegate.start || current != oldDelegate.current;
  }
}
