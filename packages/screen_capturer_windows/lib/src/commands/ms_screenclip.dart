import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';
import 'package:screen_capturer_windows/src/widgets/screenshot_overlay.dart';
import 'package:win32/win32.dart';

final Map<CaptureMode, String> _knownCaptureModeArgs = {
  CaptureMode.region: 'Rectangle',
  CaptureMode.screen: '',
  CaptureMode.window: 'Window',
};

bool _isScreenClipping() {
  final int hWnd = GetForegroundWindow();
  final lpdwProcessId = calloc<Uint32>();

  GetWindowThreadProcessId(hWnd, lpdwProcessId);
  // Get a handle to the process.
  final hProcess = OpenProcess(
    PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_INFORMATION |
        PROCESS_ACCESS_RIGHTS.PROCESS_VM_READ,
    FALSE,
    lpdwProcessId.value,
  );

  if (hProcess == 0) {
    return false;
  }

  // Get a list of all the modules in this process.
  final hModules = calloc<HMODULE>(1024);
  final cbNeeded = calloc<DWORD>();

  try {
    int r = EnumProcessModules(
      hProcess,
      hModules,
      sizeOf<HMODULE>() * 1024,
      cbNeeded,
    );

    if (r == 1) {
      for (var i = 0; i < (cbNeeded.value ~/ sizeOf<HMODULE>()); i++) {
        final szModName = wsalloc(MAX_PATH);
        // Get the full path to the module's file.
        final hModule = (hModules + i).value;
        if (GetModuleFileNameEx(hProcess, hModule, szModName, MAX_PATH) != 0) {
          String moduleName = szModName.toDartString();
          if (moduleName.contains('ScreenClippingHost.exe') ||
              moduleName.contains('SnippingTool.exe')) {
            free(szModName);
            return true;
          }
        }
        free(szModName);
      }
    }
  } finally {
    free(hModules);
    free(cbNeeded);
    CloseHandle(hProcess);
  }

  return false;
}

class _MsScreenclip with SystemScreenCapturer {
  BuildContext? get _context {
    final navigatorKey = GlobalKey<NavigatorState>();
    return navigatorKey.currentContext;
  }

  Future<ui.Image?> _captureFullScreen() async {
    final displayHandle = GetDC(0);
    if (displayHandle == 0) return null;

    try {
      final screenWidth = GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
      
      final compatibleDC = CreateCompatibleDC(displayHandle);
      final bmp = CreateCompatibleBitmap(displayHandle, screenWidth, screenHeight);
      final oldBmp = SelectObject(compatibleDC, bmp);
      
      // 复制屏幕内容到位图
      BitBlt(
        compatibleDC, 0, 0, screenWidth, screenHeight,
        displayHandle, 0, 0, SRCCOPY,
      );

      // TODO: 将位图数据转换为 Flutter Image
       // Get bitmap info
      final bmi = calloc<BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = screenWidth;
      bmi.ref.bmiHeader.biHeight = -screenHeight; // Top-down DIB
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_COMPRESSION.BI_RGB;

       // Allocate memory for pixel data
      final pixels = calloc<Uint8>(screenWidth * screenHeight * 4);
      
       GetDIBits(
        compatibleDC,
        bmp,
        0,
        screenHeight,
        pixels,
        bmi,
        DIB_USAGE.DIB_RGB_COLORS,
      );
      
       // Convert to Flutter Image
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels.asTypedList(screenWidth * screenHeight * 4),
        screenWidth,
        screenHeight,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );

      // Cleanup
      free(pixels);
      free(bmi);
      SelectObject(compatibleDC, oldBmp);
      DeleteObject(bmp);
      DeleteDC(compatibleDC);
      
      return completer.future;
    } catch (e) {
      print('screenCapturer-log $e');
    }
    finally {
      ReleaseDC(0, displayHandle);
    }
    return null;
  }

  @override
  Future<void> capture({
    required CaptureMode mode,
    String? imagePath,
    bool copyToClipboard = true,
    bool silent = true,
  }) async {
    final screenImage = await _captureFullScreen();
    if (screenImage == null) return;
        
    final context = _context;
    if (context == null) {
      print('No valid context found for showing overlay');
      return;
    }
    await showScreenshotOverlay(context, screenImage, mode: mode);
  }
}
