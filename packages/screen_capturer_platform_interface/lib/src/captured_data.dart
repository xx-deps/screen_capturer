import 'dart:ui';
import 'package:json_annotation/json_annotation.dart';
import 'package:screen_retriever/screen_retriever.dart';

part 'captured_data.g.dart';

@JsonSerializable()
class CapturedDisplay {
  const CapturedDisplay({
    required this.display,
    required this.imagePath,
    required this.windows,
  });

  factory CapturedDisplay.fromJson(Map<String, dynamic> json) =>
      _$CapturedDisplayFromJson(json);

  final Display display;
  final String imagePath;
  final List<WindowInfo> windows;

  Map<String, dynamic> toJson() => _$CapturedDisplayToJson(this);

  CapturedDisplay copyWith({
    Display? display,
    String? imagePath,
    List<WindowInfo>? windows,
  }) {
    return CapturedDisplay(
      display: display ?? this.display,
      imagePath: imagePath ?? this.imagePath,
      windows: windows ?? this.windows,
    );
  }
}

@JsonSerializable(
  converters: [_RectConverter()],
)
class WindowInfo {
  const WindowInfo({
    required this.handle,
    required this.title,
    required this.bounds,
    required this.displayId,
  });

  factory WindowInfo.fromJson(Map<String, dynamic> json) =>
      _$WindowInfoFromJson(json);

  final int handle;
  final String title;
  final Rect bounds;
  final String displayId;

  Map<String, dynamic> toJson() => _$WindowInfoToJson(this);

  WindowInfo copyWith({
    int? handle,
    String? title,
    Rect? bounds,
    String? displayId,
  }) {
    return WindowInfo(
      handle: handle ?? this.handle,
      title: title ?? this.title,
      bounds: bounds ?? this.bounds,
      displayId: displayId ?? this.displayId,
    );
  }

  @override
  String toString() {
    return 'WindowInfo(handle: $handle, title: $title, bounds: $bounds, displayId: $displayId)';
  }
}

class _RectConverter extends JsonConverter<Rect, Map<String, dynamic>> {
  const _RectConverter();

  @override
  Rect fromJson(Map<String, dynamic> json) {
    return Rect.fromLTRB(
      (json['left'] as num).toDouble(),
      (json['top'] as num).toDouble(),
      (json['right'] as num).toDouble(),
      (json['bottom'] as num).toDouble(),
    );
  }

  @override
  Map<String, dynamic> toJson(Rect rect) => {
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
      };
}
