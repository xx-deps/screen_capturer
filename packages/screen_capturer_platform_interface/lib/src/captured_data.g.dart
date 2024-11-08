// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: require_trailing_commas

part of 'captured_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CapturedDisplay _$CapturedDisplayFromJson(Map<String, dynamic> json) =>
    CapturedDisplay(
      display: Display.fromJson(json['display'] as Map<String, dynamic>),
      imagePath: json['imagePath'] as String,
      windows: (json['windows'] as List<dynamic>)
          .map((e) => WindowInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CapturedDisplayToJson(CapturedDisplay instance) =>
    <String, dynamic>{
      'display': instance.display,
      'imagePath': instance.imagePath,
      'windows': instance.windows,
    };

WindowInfo _$WindowInfoFromJson(Map<String, dynamic> json) => WindowInfo(
      handle: (json['handle'] as num).toInt(),
      title: json['title'] as String,
      bounds: const _RectConverter()
          .fromJson(json['bounds'] as Map<String, dynamic>),
      displayId: json['displayId'] as String,
    );

Map<String, dynamic> _$WindowInfoToJson(WindowInfo instance) =>
    <String, dynamic>{
      'handle': instance.handle,
      'title': instance.title,
      'bounds': const _RectConverter().toJson(instance.bounds),
      'displayId': instance.displayId,
    };
