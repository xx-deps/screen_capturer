
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
    final screenDC = GetDC(NULL);
    final memDC = CreateCompatibleDC(screenDC);

    try {
      // Capture each display
      for (final display in displays) {
        if (display.visiblePosition == null || display.visibleSize == null) continue;

        final bmp = CreateCompatibleBitmap(
          screenDC, 
          display.visibleSize!.width.toInt(), 
          display.visibleSize!.height.toInt(),
        );
        
        SelectObject(memDC, bmp);
        
        BitBlt(
          memDC,
          0,
          0,
          display.visibleSize!.width.toInt(),
          display.visibleSize!.height.toInt(),
          screenDC,
          display.visiblePosition!.dx.toInt(),
          display.visiblePosition!.dy.toInt(),
          ROP_CODE.SRCCOPY,
        );
        
        displayBitmaps[display] = bmp;
      }
      for (final entry in displayBitmaps.entries) {
        final display = entry.key;
        final bmp = entry.value;

        await _showSelectionOverlay(
          screenWidth: display.visibleSize!.width.toInt(), 
          screenHeight: display.visibleSize!.height.toInt(),
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
    return displays.map((display) => CapturedDisplay
        .fromDisplay(display, '${imagePath}_${display.base64}.png'),
      ).toList();
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
}

extension DisplayExtension on Display {
  /// Converts the display ID to a URL-safe base64 string
  String get base64 => base64Url.encode(utf8.encode(id));
}
