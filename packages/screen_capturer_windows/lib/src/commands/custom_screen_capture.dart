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
  Future<List<CapturedDisplay>> captureInMultiMonitor({required String imagePath}) async {
    // Get all displays
    final displays = await ScreenRetriever.instance.getAllDisplays();
    
    // Create a map to store each display's bitmap
    final displayBitmaps = <Display, int>{};
    final displayWindows = <Display, List<WindowInfo>>{};
    final screenDC = GetDC(NULL);
    final memDC = CreateCompatibleDC(screenDC);

    try {
      // Get all windows for each display
      for (final display in displays) {
        final windows = await _getWindowsForDisplay(display);
        displayWindows[display] = windows;
      }

      // Capture each display
      for (final display in displays) {
        final visiblePosition = display.visiblePosition;
        if (visiblePosition == null) continue;

        final scaleFactor = display.scaleFactor ?? 1.0;
        final physicalWidth = (display.size.width * scaleFactor).toInt();
        final physicalHeight = (display.size.height * scaleFactor).toInt();
        final physicalX = (visiblePosition.dx * scaleFactor).toInt();
        final physicalY = (visiblePosition.dy * scaleFactor).toInt();

        final bmp = CreateCompatibleBitmap(
          screenDC, 
          physicalWidth, 
          physicalHeight,
        );
        
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
        
        if (result == 0) {
          throw WindowsException(GetLastError());
        }

        SelectObject(memDC, oldBitmap);
        displayBitmaps[display] = bmp;
      }


      for (final entry in displayBitmaps.entries) {
        final display = entry.key;
        final bmp = entry.value;
         final scaleFactor = display.scaleFactor ?? 1.0;
        final physicalWidth = (display.size.width * scaleFactor).toInt();
        final physicalHeight = (display.size.height * scaleFactor).toInt();

        await _showSelectionOverlay(
          screenWidth: physicalWidth, 
          screenHeight: physicalHeight,
          bmp: bmp, 
          imagePath: '${imagePath}_${display.base64}.png',
          );
      }
    } catch (e) {
      rethrow;
    } finally {
      for (final bmp in displayBitmaps.values) {
        DeleteObject(bmp);
      }
      DeleteObject(memDC);
      ReleaseDC(NULL, screenDC);
    }
    return displays.map((display) => CapturedDisplay(
      display: display,
      imagePath:  '${imagePath}_${display.base64}.png',
      windows: displayWindows[display] ?? [],
    ),).toList();
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
      GetDIBits(memDC, bmp, 0, screenHeight, lpBits, buffer, DIB_USAGE.DIB_RGB_COLORS);

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
    }  catch (e) {
      rethrow;
    }
    finally {
      free(buffer);
      DeleteDC(memDC);
      ReleaseDC(NULL, screenDC);
    }
  }
Future<List<WindowInfo>> _getWindowsForDisplay(Display display) async {
    final windows = <WindowInfo>[];
    final scaleFactor = display.scaleFactor ?? 1.0;
    final displayRect = ui.Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
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

            final windowRect = ui.Rect.fromLTRB(
              rect.ref.left.toDouble() / scaleFactor,
              rect.ref.top.toDouble() / scaleFactor,
              rect.ref.right.toDouble() / scaleFactor,
              rect.ref.bottom.toDouble() / scaleFactor,
            );

            // 检查窗口是否与显示器矩形相交
            if (windowRect.overlaps(displayRect)) {
              if (length > 0) {
                final buffer = wsalloc(length + 1);
                try {
                  GetWindowText(hwnd, buffer, length + 1);
                  final title = buffer.toDartString();

                  // 确保窗口坐标在显示器范围内
                  final left = windowRect.left.clamp(0, display.size.width).floorToDouble();
                  final top = windowRect.top.clamp(0, display.size.height).floorToDouble();
                  final right = windowRect.right.clamp(0, display.size.width).floorToDouble();
                  final bottom = windowRect.bottom.clamp(0, display.size.height).floorToDouble();

                  windows.add(WindowInfo(
                    handle: hwnd,
                    title: title,
                    bounds: ui.Rect.fromLTRB(left, top, right, bottom),
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
  String get base64 => base64Url.encode(utf8.encode(id));
}
