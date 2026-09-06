import 'dart:convert';

/// A physical monitor discovered via DDC/CI.
class MonitorInfo {
  final int id;
  final String drm;
  final String make;
  final String model;
  final String serial;
  final int? brightness;
  final int? contrast;

  const MonitorInfo({
    required this.id,
    required this.drm,
    required this.make,
    required this.model,
    required this.serial,
    this.brightness,
    this.contrast,
  });

  String get label => '$make $model'.trim().isEmpty ? 'Display $id' : '$make $model'.trim();

  MonitorInfo copyWith({int? brightness, int? contrast}) => MonitorInfo(
        id: id,
        drm: drm,
        make: make,
        model: model,
        serial: serial,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'drm': drm,
        'make': make,
        'model': model,
        'serial': serial,
        'label': label,
        'brightness': brightness,
        'contrast': contrast,
      };
}

/// Error with a human-actionable message (shown in UI and API responses).
class LuxException implements Exception {
  final String message;
  const LuxException(this.message);
  @override
  String toString() => 'LuxException: $message';

  Map<String, dynamic> toJson() => {'error': message};
}

/// Brightness presets applied to ALL detected monitors.
class LuxPresets {
  static const values = <String, int>{
    'night': 15,
    'reading': 35,
    'day': 80,
  };

  static bool contains(String name) => values.containsKey(name.toLowerCase());

  /// Brightness value for a preset name. Throws if unknown — check
  /// [contains] first. (Dart forbids static `operator []`, hence the method.)
  static int valueOf(String name) => values[name.toLowerCase()]!;
}

/// Minimal JSON helpers shared by the API server.
String jsonOk(Object data) => jsonEncode({'ok': true, 'data': data});
String jsonErr(String message, [int? code]) =>
    jsonEncode({'ok': false, 'error': message, if (code != null) 'code': code});
