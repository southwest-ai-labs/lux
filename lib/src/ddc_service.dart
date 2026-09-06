import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// VESA MCCS Virtual Control Panel codes (generic — same on every brand).
abstract final class Vcp {
  static const brightness = 0x10;
  static const contrast = 0x12;
  static const colorPreset = 0x14;
  static const redGain = 0x16;
  static const greenGain = 0x18;
  static const blueGain = 0x1A;

  static String hex(int code) =>
      '0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

/// Thin wrapper over the `ddcutil` CLI (DDC/CI over I2C).
///
/// This is the ONLY place that speaks to the monitors. The Flutter UI, the
/// local HTTP API and `scripts/luxctl` all go through these exact VCP codes,
/// so behaviour is identical whichever entry point an agent uses.
class DdcService {
  static const executable = 'ddcutil';

  static Future<String> _run(List<String> args) async {
    ProcessResult result;
    try {
      result = await Process.run(executable, args);
    } on ProcessException catch (e) {
      throw LuxException(
        'ddcutil not found in PATH (${e.message}). '
        'Install it (NixOS: add pkgs.ddcutil to systemPackages).',
      );
    }
    if (result.exitCode != 0) {
      throw LuxException(_friendlyError('${result.stderr}'.trim()));
    }
    return '${result.stdout}';
  }

  static String _friendlyError(String stderr) {
    if (stderr.contains('/dev/i2c') || stderr.contains('i2c-dev')) {
      return 'No I2C devices (/dev/i2c-*). Load i2c-dev: on NixOS set '
          'hardware.i2c.enable = true, add your user to the "i2c" group, '
          'rebuild and relogin. Then run: luxctl doctor';
    }
    if (stderr.contains('Permission denied')) {
      return 'Permission denied on /dev/i2c-*. Add your user to the "i2c" '
          'group and relogin (NixOS: users.users.<you>.extraGroups = ["i2c"]).';
    }
    if (stderr.contains('No displays found') ||
        stderr.contains('no displays')) {
      return 'ddcutil found no DDC/CI displays. Check the cable (DP/HDMI) '
          'and enable DDC/CI in the monitor OSD menu.';
    }
    return stderr.isEmpty ? 'ddcutil failed with an unknown error.' : stderr;
  }

  static Future<bool> get isAvailable async {
    try {
      await _run(['--version']);
      return true;
    } on LuxException {
      return false;
    }
  }

  /// Detect monitors. When [withLevels] is true, brightness/contrast are
  /// read too (slower: ~1s per monitor over I2C).
  static Future<List<MonitorInfo>> detect({bool withLevels = true}) async {
    final out = await _run(['--brief', 'detect']);
    final monitors = parseDetect(out);
    if (!withLevels) return monitors;
    final resolved = <MonitorInfo>[];
    for (final m in monitors) {
      var brightness = m.brightness;
      var contrast = m.contrast;
      try {
        brightness = (await getLevel(m.id, Vcp.brightness)).current;
      } on LuxException catch (e) {
        debugPrint('lux: brightness unreadable on display ${m.id}: $e');
      }
      try {
        contrast = (await getLevel(m.id, Vcp.contrast)).current;
      } on LuxException catch (e) {
        debugPrint('lux: contrast unreadable on display ${m.id}: $e');
      }
      resolved.add(m.copyWith(brightness: brightness, contrast: contrast));
    }
    return resolved;
  }

  /// Parse `ddcutil --brief detect`. Tolerant: unknown lines are ignored,
  /// missing make/model fall back to 'Unknown' (never throws on shape).
  static List<MonitorInfo> parseDetect(String out) {
    final monitors = <MonitorInfo>[];
    final blocks = out.split(RegExp(r'^Display\s+(\d+)\s*$', multiLine: true));
    // blocks[0] is the preamble; odd indices are ids, even are bodies.
    final ids = RegExp(r'^Display\s+(\d+)\s*$', multiLine: true)
        .allMatches(out)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    for (var i = 0; i < ids.length; i++) {
      final body = i + 1 < blocks.length ? blocks[i + 1] : '';
      String field(RegExp re) =>
          re.firstMatch(body)?.group(1)?.trim() ?? '';
      final drm = field(RegExp(r'DRM connector:\s*(\S+)'));
      var make = field(RegExp(r'Mfg id:\s*(.+)'));
      var model = field(RegExp(r'Model:\s*(.+)'));
      var serial = field(RegExp(r'Serial number:\s*(\S+)'));
      // Some firmwares report "Monitor: MFG:MODEL:SERIAL" in one line.
      final packed = field(RegExp(r'^\s*Monitor:\s*(.+)$', multiLine: true));
      if (packed.isNotEmpty) {
        final parts = packed.split(':');
        if (make.isEmpty && parts.isNotEmpty) make = parts[0].trim();
        if (model.isEmpty && parts.length > 1) model = parts[1].trim();
        if (serial.isEmpty && parts.length > 2) serial = parts[2].trim();
      }
      monitors.add(MonitorInfo(
        id: ids[i],
        drm: drm.isEmpty ? 'unknown' : drm,
        make: make.isEmpty ? 'Unknown' : make,
        model: model.isEmpty ? 'Unknown' : model,
        serial: serial.isEmpty ? 'unknown' : serial,
      ));
    }
    return monitors;
  }

  /// Current/max for a VCP feature. Throws [LuxException] when the monitor
  /// does not implement the feature (common on cheap panels).
  static Future<({int current, int max})> getLevel(int id, int vcp) async {
    final out = await _run(
        ['--brief', '--display', '$id', 'getvcp', _hexNoPrefix(vcp)]);
    return parseGetvcpBrief(out, vcp);
  }

  /// Parse `ddcutil --brief getvcp` (e.g. "VCP 10 C 45 100").
  static ({int current, int max}) parseGetvcpBrief(String out, int vcp) {
    final code = _hexNoPrefix(vcp);
    final m = RegExp(
      r'VCP\s+' + code + r'\s+\S+\s+(\d+)\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(out);
    if (m == null) {
      throw LuxException(
        'Monitor does not report ${Vcp.hex(vcp)} '
        '(unsupported feature or DDC/CI disabled in OSD). Raw: ${out.trim()}',
      );
    }
    return (current: int.parse(m.group(1)!), max: int.parse(m.group(2)!));
  }

  static Future<void> setBrightness(int id, int value) =>
      _setLevel(id, Vcp.brightness, value);

  static Future<void> setContrast(int id, int value) =>
      _setLevel(id, Vcp.contrast, value);

  static Future<void> _setLevel(int id, int vcp, int value) async {
    final v = value.clamp(0, 100);
    await _run(['--display', '$id', 'setvcp', _hexNoPrefix(vcp), '$v']);
  }

  /// Set the same brightness on every detected monitor.
  /// Returns per-monitor errors (null = ok). Empty map = none detected.
  static Future<Map<int, String?>> setAllBrightness(int value) async {
    final monitors = await detect(withLevels: false);
    final results = <int, String?>{};
    for (final m in monitors) {
      try {
        await setBrightness(m.id, value);
        results[m.id] = null;
      } on LuxException catch (e) {
        results[m.id] = e.message;
      }
    }
    return results;
  }

  /// Apply a named preset ([LuxPresets]) to every detected monitor.
  static Future<Map<int, String?>> applyPreset(String name) async {
    if (!LuxPresets.contains(name)) {
      throw LuxException(
          'Unknown preset "$name". Valid: ${LuxPresets.values.keys.join(', ')}');
    }
    return setAllBrightness(LuxPresets.valueOf(name));
  }

  static String _hexNoPrefix(int code) =>
      code.toRadixString(16).toUpperCase().padLeft(2, '0');
}
