
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:screen_capturer_platform_interface/screen_capturer_platform_interface.dart';
import 'package:win32/win32.dart';

// 在文件顶部添加
const CF_DIB = 8;
const GMEM_MOVEABLE = 0x0002;

class CustomScreenCapture with SystemScreenCapturer {
  @override
  Future<void> capture({
    required CaptureMode mode,
    String? imagePath,
    bool copyToClipboard = true,
    bool silent = true,
  }) async {
    // First capture the entire screen
    final screenDC = GetDC(NULL);
    final memDC = CreateCompatibleDC(screenDC);
    
    final screenWidth = GetSystemMetrics(SM_CXSCREEN);
    final screenHeight = GetSystemMetrics(SM_CYSCREEN);
    
    final bmp = CreateCompatibleBitmap(screenDC, screenWidth, screenHeight);
    SelectObject(memDC, bmp);
    
    // Copy screen content to bitmap
    BitBlt(
      memDC, 
      0, 
      0, 
      screenWidth, 
      screenHeight, 
      screenDC, 
      0, 
      0, 
      SRCCOPY,
    );

    // Show overlay window with the captured screen and mask
    await _showSelectionOverlay(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      bmp: bmp,
      imagePath: imagePath,
      copyToClipboard: copyToClipboard,
    );

    // Cleanup
    DeleteObject(bmp);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
  }

  Future<void> _showSelectionOverlay({
    required int screenWidth,
    required int screenHeight,
    required int bmp,
    required String? imagePath,
    required bool copyToClipboard,
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
      buffer.ref.bmiHeader.biCompression = BI_RGB;

      // 分配内存并获取位图数据
      final lpBits = calloc<Uint8>(screenWidth * screenHeight * 4);
      GetDIBits(memDC, bmp, 0, screenHeight, lpBits, buffer, DIB_RGB_COLORS);

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

           // 复制到剪贴板（如果需要）
      if (copyToClipboard) {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          
          // 打开剪贴板
          if (OpenClipboard(NULL) != 0) {
            try {
              // 清空剪贴板
              EmptyClipboard();
              
              // 分配全局内存
              final hMem = GlobalAlloc(GMEM_MOVEABLE, pngBytes.length);
              final pMem = GlobalLock(hMem);
              
              // 复制数据到全局内存
              final dest = pMem.cast<Uint8>();
              for (var i = 0; i < pngBytes.length; i++) {
                dest[i] = pngBytes[i];
              }
              
              GlobalUnlock(hMem);
              
              // 设置剪贴板数据
              SetClipboardData(CF_DIB, hMem.address);
            } finally {
              // 关闭剪贴板
              CloseClipboard();
            }
          }
        }
      }

      free(lpBits);
    } finally {
      free(buffer);
      DeleteDC(memDC);
      ReleaseDC(NULL, screenDC);
    }
  }
}

class OverlayWindow extends StatefulWidget {

  const OverlayWindow({
    required this.width,
    required this.height,
    required this.bitmap,
    super.key,
  });

  static final navigatorKey = GlobalKey<NavigatorState>();

  final double width;
  final double height;
  final int bitmap;

  Future<Rect?> show() async {
    return showDialog<Rect>(
      context: navigatorKey.currentContext!,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: this,
      ),
    );
  }

  @override
  State<OverlayWindow> createState() => _OverlayWindowState();
}

class _OverlayWindowState extends State<OverlayWindow> {
  Offset? _startPoint;
  Rect? selectedRegion;
  ui.Image? _screenImage;

  @override
  void initState() {
    super.initState();
    _convertBitmapToImage();
  }

  Future<void> _convertBitmapToImage() async {
    final screenDC = GetDC(NULL);
    final memDC = CreateCompatibleDC(screenDC);
    final width = widget.width.toInt();
    final height = widget.height.toInt();
    
    final buffer = calloc<BITMAPINFO>();
    buffer.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    buffer.ref.bmiHeader.biWidth = width;
    buffer.ref.bmiHeader.biHeight = -height; // Top-down
    buffer.ref.bmiHeader.biPlanes = 1;
    buffer.ref.bmiHeader.biBitCount = 32;

    final lpBits = calloc<Uint8>(width * height * 4);
    GetDIBits(memDC, widget.bitmap, 0, height, lpBits, buffer, DIB_RGB_COLORS);

    final bytes = lpBits.asTypedList(width * height * 4);
    final completer = Completer<ui.Image>();
    
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );

    _screenImage = await completer.future;
    setState(() {});

    free(lpBits);
    free(buffer);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_screenImage != null)
          RawImage(image: _screenImage),
        
        Container(color: Colors.black.withOpacity(0.3)),
        
        if (selectedRegion != null)
          Positioned(
            left: selectedRegion!.left,
            top: selectedRegion!.top,
            width: selectedRegion!.width,
            height: selectedRegion!.height,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                color: Colors.transparent,
              ),
            ),
          ),
        
        GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
        ),
      ],
    );
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _startPoint = details.localPosition;
      selectedRegion = Rect.fromPoints(_startPoint!, _startPoint!);
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_startPoint == null) return;
    setState(() {
      selectedRegion = Rect.fromPoints(_startPoint!, details.localPosition);
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (selectedRegion != null) {
      Navigator.of(context).pop(selectedRegion);
    }
  }
}
