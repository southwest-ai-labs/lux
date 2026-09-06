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

  /// Input source (VCP 0x60). ONLY values from `capabilities`
  /// (this AOC: 0x0F DP-1, 0x11 HDMI-1). Anything else risks signal loss.
  static const inputSourcesAllowed = {0x0F, 0x11};

  static Future<void> setInputSource(int id, int value) async {
    if (!inputSourcesAllowed.contains(value)) {
      throw LuxException(
        'Input ${Vcp.hex(value)} not offered by this panel. '
        'Allowed: ${inputSourcesAllowed.map(Vcp.hex).join(', ')}.',
      );
    }
    await _run(
        ['--display', '$id', 'setvcp', _hexNoPrefix(0x60), '$value']);
  }

  /// Parse single-NC brief read, e.g. "VCP 60 SNC x0f".
  static int parseSingleNcBrief(String out, int feature) {
    final m = RegExp(r'x([0-9a-fA-F]+)\s*$').firstMatch(out.trim());
    if (m == null) {
      throw LuxException(
          'Could not read ${Vcp.hex(feature)}. Raw: ${out.trim()}');
    }
    return int.parse(m.group(1)!, radix: 16);
  }

  static Future<int> getInputSource(int id) async {
    final out = await _run(
        ['--brief', '--display', '$id', 'getvcp', _hexNoPrefix(0x60)]);
    return parseSingleNcBrief(out, 0x60);
  }

  /// Speaker volume (VCP 0x62, 0-100 continuous). Round-trip verified.
  static Future<int> getVolume(int id) async =>
      (await getLevel(id, 0x62)).current;

  static Future<void> setVolume(int id, int value) =>
      _setLevel(id, 0x62, value);

  /// Power mode (VCP 0xD6): 1 = on, 4 = off. Verified off->on wakes the
  /// panel over DDC. Values 2/3 (standby/suspend) NOT exposed: wake
  /// behavior is panel-specific and untested here.
  static const powerModesAllowed = {0x01, 0x04};

  static Future<void> setPower(int id, bool on) async {
    final value = on ? 0x01 : 0x04;
    await _run(
        ['--display', '$id', 'setvcp', _hexNoPrefix(0xD6), '$value']);
  }

  static Future<int> getPower(int id) async {
    final out = await _run(
        ['--brief', '--display', '$id', 'getvcp', _hexNoPrefix(0xD6)]);
    return parseSingleNcBrief(out, 0xD6);
  }

  /// Hardware color presets (VCP 0x14). ONLY values reported by
  /// `capabilities` are accepted — never invent codes (0x60 input source
  /// and 0x04/0x05/0x08 resets are rejected even if passed).
  static const colorPresetsAllowed = {0x05, 0x06, 0x08, 0x0B};
  static const userPreset = 0x0B;

  static const rgbChannels = {0x16, 0x18, 0x1A};

  static Future<void> setColorPreset(int id, int value) async {
    if (!colorPresetsAllowed.contains(value)) {
      throw LuxException(
        'Preset ${Vcp.hex(value)} not offered by this panel. '
        'Allowed: ${colorPresetsAllowed.map(Vcp.hex).join(', ')}.',
      );
    }
    await _run(
        ['--display', '$id', 'setvcp', _hexNoPrefix(0x14), '$value']);
  }

  /// Parse brief non-continuous read, e.g. "VCP 14 CNC x00 x0b x00 x05"
  /// (current value = last hex token).
  static int parseColorPresetBrief(String out) {
    final m = RegExp(r'x([0-9a-fA-F]+)\s*$').firstMatch(out.trim());
    if (m == null) {
      throw LuxException(
          'Could not read color preset. Raw: ${out.trim()}');
    }
    return int.parse(m.group(1)!, radix: 16);
  }

  static Future<int> getColorPreset(int id) async {
    final out = await _run(
        ['--brief', '--display', '$id', 'getvcp', _hexNoPrefix(0x14)]);
    return parseColorPresetBrief(out);
  }

  /// Set one RGB gain. Panels (verified AOC) only honor gains in User
  /// preset, so this switches to User1 (0x0B) first — explicit by design.
  static Future<void> setUserGain(int id, int channel, int value) async {
    if (!rgbChannels.contains(channel)) {
      throw LuxException(
        'Bad gain channel ${Vcp.hex(channel)}. Use 0x16/0x18/0x1A.',
      );
    }
    await setColorPreset(id, userPreset);
    await _setLevel(id, channel, value);
  }

  static Future<({int r, int g, int b})> getRgbGains(int id) async {
    Future<int> read(int channel) =>
        getLevel(id, channel).then((v) => v.current);
    return (
      r: await read(Vcp.redGain),
      g: await read(Vcp.greenGain),
      b: await read(Vcp.blueGain),
    );
  }
}
