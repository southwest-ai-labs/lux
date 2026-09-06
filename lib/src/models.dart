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

/// A display profile: hardware backlight + software color temperature.
///
/// Brightness needs DDC/CI (i2c); temperature works right now via wlsunset.
/// Both are applied best-effort and reported per part, so a profile is
/// useful even before the NixOS i2c setup.
class ColorProfile {
  final String name;
  final String label;
  final String description;
  final int brightness;
  final int temperature;

  const ColorProfile({
    required this.name,
    required this.label,
    required this.description,
    required this.brightness,
    required this.temperature,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'description': description,
        'brightness': brightness,
        'temperature': temperature,
      };
}

abstract final class ColorProfiles {
  static const gaming = ColorProfile(
    name: 'gaming',
    label: 'Jugar',
    description: 'Brillo alto, color neutro y vivido.',
    brightness: 90,
    temperature: 6500,
  );
  static const code = ColorProfile(
    name: 'code',
    label: 'Programar',
    description: 'Brillo medio, blanco suave, sin fatiga.',
    brightness: 65,
    temperature: 5500,
  );
  static const video = ColorProfile(
    name: 'video',
    label: 'Ver videos',
    description: 'Sala tenue, cálido de cine.',
    brightness: 45,
    temperature: 4500,
  );
  static const read = ColorProfile(
    name: 'read',
    label: 'Leer',
    description: 'Cálido papel, mínimo azul.',
    brightness: 35,
    temperature: 4000,
  );

  static const all = [gaming, code, video, read];

  static const _aliases = {
    'gaming': 'gaming', 'jugar': 'gaming', 'juego': 'gaming', 'game': 'gaming',
    'code': 'code', 'programar': 'code', 'programacion': 'code', 'coding': 'code',
    'video': 'video', 'videos': 'video', 'cine': 'video', 'pelis': 'video', 'movie': 'video',
    'read': 'read', 'leer': 'read', 'lectura': 'read', 'reading': 'read',
  };

  static String get validNames => all.map((p) => p.name).join(', ');

  static ColorProfile? byName(String name) {
    final key = _aliases[name.toLowerCase().trim()];
    if (key == null) return null;
    return all.firstWhere((p) => p.name == key);
  }
}

/// Hardware color tone from the panel's own VCP 0x14 presets
/// (verified on AOC 24G42HE/Q27G4D firmware: 6500/7500/9300/User1).
/// The panel cannot go below 6500K in hardware — warmth comes from
/// hyprshade shaders (see ColorProfiles). Cool tones are best in
/// hardware: zero overhead, works fullscreen/in games.
class HwTone {
  final String name;
  final String label;
  final String description;
  final int preset14;

  const HwTone({
    required this.name,
    required this.label,
    required this.description,
    required this.preset14,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'description': description,
        'preset14': '0x${preset14.toRadixString(16).toUpperCase().padLeft(2, '0')}',
      };
}

abstract final class HwTones {
  static const srgb = HwTone(
    name: 'srgb',
    label: 'sRGB 6500K',
    description: 'Neutro de referencia (lo más cercano a sRGB en este panel).',
    preset14: 0x05,
  );
  static const cool75 = HwTone(
    name: 'cool75',
    label: 'Frío 7500K',
    description: 'Blancos más fríos, más contraste percibido.',
    preset14: 0x06,
  );
  static const cool93 = HwTone(
    name: 'cool93',
    label: 'Frío 9300K',
    description: 'Máximo frío del panel. Solo gusto.',
    preset14: 0x08,
  );

  static const all = [srgb, cool75, cool93];

  static const _aliases = {
    'srgb': 'srgb', '6500': 'srgb', 'neutro': 'srgb',
    'cool75': 'cool75', '7500': 'cool75', 'frio75': 'cool75',
    'cool93': 'cool93', '9300': 'cool93', 'frio93': 'cool93',
  };

  static String get validNames => all.map((p) => p.name).join(', ');

  static HwTone? byName(String name) {
    final key = _aliases[name.toLowerCase().trim()];
    if (key == null) return null;
    return all.firstWhere((p) => p.name == key);
  }
}
