import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ddc_service.dart';
import 'models.dart';
import 'process_runner.dart';

/// Software color via hyprshade screen shaders (compositor-side).
///
/// Chosen over wlsunset because this machine's wlr gamma path is broken
/// ("gamma control of output DP-2 failed" even for the user's own geo
/// wlsunset). Shaders bypass gamma entirely and are proven with captured
/// frames (lux-read: blue 18.0 -> 11.5, R/B 1.015 -> 1.539).
/// Shaders live in ~/.config/hypr/shaders/ as lux-NAME.glsl;
/// [clearTemperature] runs `hyprshade off` (unfiltered output).
/// The user's wlsunset is left alone (it fails silently, no conflict).
class ColorService {
  static const executable = 'hyprshade';

  static String shaderFor(String profileName) => 'lux-$profileName';
  static List<String> onArgs(String profileName) =>
      ['on', shaderFor(profileName)];
  static List<String> get offArgs => ['off'];

  /// Nearest profile shader for an arbitrary kelvin request.
  /// >=6000K is neutral: no shader (off).
  static String shaderForKelvin(int kelvin) {
    if (kelvin >= 6000) return 'off';
    if (kelvin >= 5000) return shaderFor('code');
    if (kelvin >= 4250) return shaderFor('video');
    return shaderFor('read');
  }

  static Future<bool> get isAvailable async {
    try {
      final r = await Shell.run('which', [executable]);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Apply a named profile: hardware brightness (best-effort, needs i2c)
  /// + hyprshade color (works now). Failures come back per part.
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
      final failed = perMonitor.values.where((e) => e != null).length;
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
      await setShader(profile.name);
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
        'shader': shaderFor(profile.name),
        'error': temperatureError,
      },
    };
  }

  /// Activate a profile shader. Throws [LuxException] with hyprshade's
  /// stderr when it fails (shader missing, compositor unreachable).
  static Future<void> setShader(String profileName) async {
    await _runHyprshade(onArgs(profileName));
    debugPrint('lux: shader ${shaderFor(profileName)} on');
  }

  /// Back to unfiltered output. Never throws (shutdown path).
  static Future<void> clearTemperature() async {
    try {
      await _runHyprshade(offArgs);
    } catch (e) {
      debugPrint('lux: clear failed: $e');
    }
  }

  static Future<void> shutdown() async => clearTemperature();

  static Future<String?> currentShader() async {
    try {
      final r = await Shell.runTool(executable, ['current']);
      if (r.exitCode != 0) return null;
      final out = '${r.stdout}'.trim();
      return out.isEmpty ? null : out;
    } on ProcessException {
      return null;
    }
  }

  static Future<void> _runHyprshade(List<String> args) async {
    ProcessResult r;
    try {
      r = await Shell.runTool(executable, args);
    } on ProcessException catch (e) {
      throw LuxException(
          'hyprshade not found in PATH (${e.message}). NixOS: nix profile install nixpkgs#hyprshade.');
    }
    if (r.exitCode != 0) {
      throw LuxException('hyprshade ${args.join(' ')} failed: '
          '${'${r.stderr}'.trim()}');
    }
  }
}
