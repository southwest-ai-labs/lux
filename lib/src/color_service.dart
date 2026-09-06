import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ddc_service.dart';
import 'models.dart';

/// Software color-temperature control via `wlsunset`.
///
/// Taking over gamma kills the user's own wlsunset (e.g. geo night-light),
/// so the previous command line is saved to `~/.config/lux/wlsunset.prev`
/// and relaunched on [clearTemperature]/[shutdown]. Taking over twice keeps
/// the FIRST saved command (first owner wins) so restore never loops.
class ColorService {
  static const executable = 'wlsunset';
  static Process? _active;

  /// Args that hold ~[kelvin] constant. wlsunset requires high > low
  /// (strict), so we pin low = K-1, high = K — a ±1K difference no eye
  /// can see, stable day and night without needing geo coordinates.
  static List<String> argsForTemp(int kelvin) =>
      ['-t', '${kelvin - 1}', '-T', '$kelvin'];

  static bool isValidTemp(int kelvin) => kelvin >= 1000 && kelvin <= 10000;

  static Future<bool> get isAvailable async {
    try {
      final r = await Process.run('which', [executable]);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<File> _stateFile() async {
    final base = Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    final dir = Directory('$base${Platform.pathSeparator}lux');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}wlsunset.prev');
  }

  /// Command line (args only) of a wlsunset NOT owned by us, if any.
  static Future<List<String>?> _otherWlsunsetArgs() async {
    final r = await Process.run('pgrep', ['-a', '-x', executable]);
    if (r.exitCode != 0) return null;
    final ownPid = _active?.pid;
    for (final line in '${r.stdout}'.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      if (ownPid != null && int.tryParse(parts[0]) == ownPid) continue;
      return parts.sublist(2);
    }
    return null;
  }

  /// Apply a named profile: hardware brightness (best-effort, needs i2c)
  /// + software temperature (works now). Never throws the aggregate —
  /// failures come back per part in the result map.
  static Future<Map<String, dynamic>> applyProfile(String name) async {
    final profile = ColorProfiles.byName(name);
    if (profile == null) {
      throw LuxException(
          'Unknown profile "$name". Valid: ${ColorProfiles.validNames}');
    }
    String? brightnessError;
    Map<int, String?> perMonitor = {};
    try {
      perMonitor = await DdcService.setAllBrightness(profile.brightness);
      final failed =
          perMonitor.values.where((e) => e != null).length;
      if (perMonitor.isEmpty) {
        brightnessError = 'No DDC/CI monitors reachable (needs i2c).';
      } else if (failed == perMonitor.length) {
        brightnessError = perMonitor.values.first;
      }
    } on LuxException catch (e) {
      brightnessError = e.message;
    }
    String? temperatureError;
    try {
      await setTemperature(profile.temperature);
    } on LuxException catch (e) {
      temperatureError = e.message;
    }
    return {
      'profile': profile.name,
      'brightness': {
        'target': profile.brightness,
        'error': brightnessError,
        'perMonitor': perMonitor
            .map((k, v) => MapEntry('$k', v == null ? 'ok' : 'error: $v')),
      },
      'temperature': {
        'target': profile.temperature,
        'error': temperatureError,
      },
    };
  }

  /// Hold [kelvin] via wlsunset, taking over gamma. Restorable.
  static Future<void> setTemperature(int kelvin) async {
    if (!isValidTemp(kelvin)) {
      throw const LuxException('Temperature must be 1000-10000 K.');
    }
    if (!await isAvailable) {
      throw const LuxException(
          'wlsunset not found in PATH (NixOS: pkgs.wlsunset).');
    }
    final other = await _otherWlsunsetArgs();
    if (other != null) {
      final state = await _stateFile();
      if (!await state.exists()) {
        await state.writeAsString(jsonEncode({'args': other}));
      }
    }
    await _killAll();
    try {
      _active = await Process.start(executable, argsForTemp(kelvin));
    } on ProcessException catch (e) {
      throw LuxException('Could not start wlsunset: ${e.message}');
    }
    _active!.stdout.listen((_) {});
    _active!.stderr.listen((_) {});
    unawaited(_active!.exitCode);
    debugPrint('lux: holding $kelvin K via wlsunset (pid ${_active!.pid})');
  }

  /// Release gamma: kill ours and relaunch whatever was running before.
  static Future<void> clearTemperature() async {
    await _killAll();
    final state = await _stateFile();
    if (await state.exists()) {
      try {
        final saved =
            jsonDecode(await state.readAsString()) as Map<String, dynamic>;
        final args = (saved['args'] as List).cast<String>();
        final restored = await Process.start(executable, args);
        restored.stdout.listen((_) {});
        restored.stderr.listen((_) {});
        unawaited(restored.exitCode);
        debugPrint('lux: restored previous wlsunset ${args.join(' ')}');
      } catch (e) {
        debugPrint('lux: restore failed: $e');
      } finally {
        try {
          await state.delete();
        } catch (_) {}
      }
    }
  }

  /// App shutdown: same as clear, never throws.
  static Future<void> shutdown() async {
    try {
      await clearTemperature();
    } catch (e) {
      debugPrint('lux: shutdown restore failed: $e');
    }
  }

  static Future<void> _killAll() async {
    _active?.kill();
    _active = null;
    try {
      await Process.run('pkill', ['-x', executable]);
    } on ProcessException {
      // pkill missing or nothing to kill — fine.
    }
  }
}
