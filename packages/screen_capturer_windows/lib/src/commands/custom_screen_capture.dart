import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart';

class CustomScreenCapture with SystemScreenCapturer {
  @override
  Future<List<CapturedDisplay>> captureInMultiMonitor(
      {required String imagePath}) async {
    final displays = await ScreenRetriever.instance.getAllDisplays();
    final displayWindows = <Display, List<WindowInfo>>{};

    // 先并发获取所有窗口信息
    await Future.wait(displays.map((display) async {
      displayWindows[display] = await _getWindowsForDisplay(display);
    }));

    // 并发捕获和保存每个屏幕
    final results = await Future.wait(displays.map((display) async {
      final visiblePosition = display.visiblePosition;
      if (visiblePosition == null) return null;

      return CapturedDisplay(
        display: display,
        imagePath: '${imagePath}_${display.base64}.png',
        windows: displayWindows[display] ?? [],
      );
    }));

    // 过滤掉为 null 的（visiblePosition 为空的屏幕）
    return results.whereType<CapturedDisplay>().toList();
  }

  Future<List<WindowInfo>> _getWindowsForDisplay(Display display) async {
    final windows = <WindowInfo>[];
    final scaleFactor = display.scaleFactor ?? 1.0;
    final displayX = display.visiblePosition?.dx ?? 0;
    final displayY = display.visiblePosition?.dy ?? 0;
    final displayRect = ui.Rect.fromLTWH(
      displayX,
      displayY,
      display.size.width,
      display.size.height,
    );

    final enumWindowsCallback = NativeCallable<WNDENUMPROC>.isolateLocal(
      (int hwnd, int lParam) {
        if (IsWindowVisible(hwnd) != 0) {
          final rect = calloc<RECT>();
          try {
            // 使用 DwmGetWindowAttribute 获取实际窗口边界（不包括阴影）
            final hr = DwmGetWindowAttribute(
              hwnd,
              DWMWINDOWATTRIBUTE.DWMWA_EXTENDED_FRAME_BOUNDS,
              rect,
              sizeOf<RECT>(),
            );

            // 如果 DwmGetWindowAttribute 失败，回退到 GetWindowRect
            if (FAILED(hr)) {
              GetWindowRect(hwnd, rect);
            }

            final length = GetWindowTextLength(hwnd);

            // 获取绝对坐标
            final absoluteRect = ui.Rect.fromLTRB(
              rect.ref.left.toDouble() / scaleFactor,
              rect.ref.top.toDouble() / scaleFactor,
              rect.ref.right.toDouble() / scaleFactor,
              rect.ref.bottom.toDouble() / scaleFactor,
            );

            // 检查窗口是否与显示器矩形相交
            if (absoluteRect.overlaps(displayRect)) {
              if (length > 0) {
                final buffer = wsalloc(length + 1);
                try {
                  GetWindowText(hwnd, buffer, length + 1);
                  final title = buffer.toDartString();

                  // 转换为相对于当前显示器的坐标
                  final relativeLeft = (absoluteRect.left - displayX)
                      .clamp(0.0, display.size.width);
                  final relativeTop = (absoluteRect.top - displayY)
                      .clamp(0.0, display.size.height);
                  final relativeRight = (absoluteRect.right - displayX)
                      .clamp(0.0, display.size.width);
                  final relativeBottom = (absoluteRect.bottom - displayY)
                      .clamp(0.0, display.size.height);

                  windows.add(WindowInfo(
                    handle: hwnd,
                    title: title,
                    bounds: ui.Rect.fromLTRB(
                      relativeLeft,
                      relativeTop,
                      relativeRight,
                      relativeBottom,
                    ),
                    displayId: display.id,
                  ));
                } finally {
                  free(buffer);
                }
              }
            }
          } finally {
            free(rect);
          }
        }
        return TRUE;
      },
      exceptionalReturn: 0,
    );

    try {
      EnumWindows(enumWindowsCallback.nativeFunction, 0);
    } finally {
      enumWindowsCallback.close();
    }

    return windows;
  }
}

extension DisplayExtension on Display {
  /// Converts the display ID to a URL-safe base64 string
  /// If ID is null or empty, returns a fallback value
  String get base64 {
    if (id.isEmpty) {
      // Generate a fallback ID using display properties
      final fallbackId = 'display_${size.width.toInt()}x${size.height.toInt()}_' +
          '${visiblePosition?.dx.toInt() ?? 0}_${visiblePosition?.dy.toInt() ?? 0}';
      return fallbackId;
    }
    return base64Url.encode(utf8.encode(id));
  }
}
