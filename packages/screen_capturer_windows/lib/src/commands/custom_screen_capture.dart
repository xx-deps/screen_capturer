import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
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

      final scaleFactor = display.scaleFactor ?? 1.0;
      final physicalWidth = (display.size.width * scaleFactor).toInt();
      final physicalHeight = (display.size.height * scaleFactor).toInt();
      final physicalX = (visiblePosition.dx * scaleFactor).toInt();
      final physicalY = (visiblePosition.dy * scaleFactor).toInt();

      final screenDC = GetDC(NULL);
      final memDC = CreateCompatibleDC(screenDC);

      try {
        final bmp =
            CreateCompatibleBitmap(screenDC, physicalWidth, physicalHeight);
        final oldBitmap = SelectObject(memDC, bmp);

        final result = BitBlt(
          memDC,
          0,
          0,
          physicalWidth,
          physicalHeight,
          screenDC,
          physicalX,
          physicalY,
          ROP_CODE.SRCCOPY,
        );

        SelectObject(memDC, oldBitmap);

        if (result == 0) {
          throw WindowsException(GetLastError());
        }

        await _showSelectionOverlay(
          screenWidth: physicalWidth,
          screenHeight: physicalHeight,
          bmp: bmp,
          imagePath: '${imagePath}_${display.base64}.png',
        );

        DeleteObject(bmp);
        DeleteDC(memDC);
        ReleaseDC(NULL, screenDC);

        return CapturedDisplay(
          display: display,
          imagePath: '${imagePath}_${display.base64}.png',
          windows: displayWindows[display] ?? [],
        );
      } catch (e) {
        DeleteDC(memDC);
        ReleaseDC(NULL, screenDC);
        rethrow;
      }
    }));

    // 过滤掉为 null 的（visiblePosition 为空的屏幕）
    return results.whereType<CapturedDisplay>().toList();
  }

  Future<void> _showSelectionOverlay({
    required int screenWidth,
    required int screenHeight,
    required int bmp,
    required String? imagePath,
  }) async {
    final buffer = calloc<BITMAPINFO>();
    final screenDC = GetDC(NULL);
    final memDC = CreateCompatibleDC(screenDC);

    try {
      // 设置位图信息
      buffer.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      buffer.ref.bmiHeader.biWidth = screenWidth;
      buffer.ref.bmiHeader.biHeight = -screenHeight; // Top-down
      buffer.ref.bmiHeader.biPlanes = 1;
      buffer.ref.bmiHeader.biBitCount = 32;
      buffer.ref.bmiHeader.biCompression = BI_COMPRESSION.BI_RGB;

      // 分配内存并获取位图数据
      final lpBits = calloc<Uint8>(screenWidth * screenHeight * 4);
      GetDIBits(memDC, bmp, 0, screenHeight, lpBits, buffer,
          DIB_USAGE.DIB_RGB_COLORS);

      final bytes = lpBits.asTypedList(screenWidth * screenHeight * 4);

      // 转换为图片
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        screenWidth,
        screenHeight,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );

      final image = await completer.future;

      // 保存图片到文件（如果提供了路径）
      if (imagePath != null) {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          await File(imagePath).writeAsBytes(pngBytes);
        }
      }

      free(lpBits);
    } catch (e) {
      rethrow;
    } finally {
      free(buffer);
      DeleteDC(memDC);
      ReleaseDC(NULL, screenDC);
    }
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
