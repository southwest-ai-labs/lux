import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'color_service.dart';
import 'ddc_service.dart';
import 'models.dart';

/// Localhost-only HTTP API so LLM agents and scripts can drive Lux.
///
///   GET    /v1/health
///   GET    /v1/monitors
///   GET    /v1/monitors/:id
///   PUT    /v1/monitors/:id          {brightness?, contrast?}
///   POST   /v1/presets/:name         night | reading | day
///   GET    /v1/skill                 usage summary for agents
///
/// Auth: `Authorization: Bearer <token>`, token at ~/.config/lux/token
/// (0600). Health is open; everything else requires the token. The server
/// binds 127.0.0.1 ONLY — never exposed to the LAN.
class LuxApiServer {
  static const defaultPort = 19847;

  final HttpServer _server;
  final String token;
  final String tokenPath;

  LuxApiServer._(this._server, this.token, this.tokenPath);

  int get port => _server.port;

  /// Start the server. Throws [LuxException] when the port is busy.
  static Future<LuxApiServer> start({int port = defaultPort}) async {
    final cfg = await _configDir();
    final tokenPath =
        '${cfg.path}${Platform.pathSeparator}token';
    final token = await _loadOrCreateToken(File(tokenPath));
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw LuxException(
          'Port $port is busy — another Lux instance is already running.');
    }
    final api = LuxApiServer._(server, token, tokenPath);
    server.listen(api._handle);
    debugPrint('lux: api listening on 127.0.0.1:${server.port}');
    return api;
  }

  /// Null-safe variant for app startup (API failure must not kill the UI).
  static Future<LuxApiServer?> tryStart({int port = defaultPort}) async {
    try {
      return await start(port: port);
    } on LuxException catch (e) {
      debugPrint('lux: api disabled: $e');
      return null;
    }
  }

  Future<void> stop() => _server.close(force: true);

  static Future<Directory> _configDir() async {
    final base = Platform.environment['XDG_CONFIG_HOME'] ??
        '${Platform.environment['HOME']}/.config';
    final dir = Directory('$base${Platform.pathSeparator}lux');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String> _loadOrCreateToken(File file) async {
    if (await file.exists()) {
      final saved = (await file.readAsString()).trim();
      if (saved.length >= 32) return saved;
    }
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final token = base64UrlEncode(bytes);
    await file.writeAsString('$token\n');
    try {
      await Process.run('chmod', ['600', file.path]);
    } on ProcessException {
      // Non-POSIX platform: best effort only.
    }
    return token;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final seg = req.uri.pathSegments;
      if (seg.length >= 2 && seg[0] == 'v1' && seg[1] == 'health') {
        return _ok(req, {
          'version': '0.3.0',
          'ddcAvailable': await DdcService.isAvailable,
        });
      }
      if (!_authorized(req)) {
        return _err(req, HttpStatus.unauthorized,
            'Missing or invalid token. See ~/.config/lux/token');
      }
      if (seg.length >= 2 && seg[0] == 'v1' && seg[1] == 'skill') {
        return _ok(req, _skillJson());
      }
      if (seg.length >= 2 && seg[0] == 'v1' && seg[1] == 'monitors') {
        if (seg.length == 2 && req.method == 'GET') {
          final monitors = await DdcService.detect();
          return _ok(req, monitors.map((m) => m.toJson()).toList());
        }
        if (seg.length == 3) {
          final id = int.tryParse(seg[2]);
          if (id == null) return _err(req, 400, 'Invalid monitor id.');
          if (req.method == 'GET') {
            final m = await _find(id);
            return _ok(req, m.toJson());
          }
          if (req.method == 'PUT') {
            final body = await _jsonBody(req);
            final b = (body['brightness'] as num?)?.toInt();
            final c = (body['contrast'] as num?)?.toInt();
            final preset = (body['colorPreset'] as num?)?.toInt();
            final r = (body['redGain'] as num?)?.toInt();
            final g = (body['greenGain'] as num?)?.toInt();
            final bl = (body['blueGain'] as num?)?.toInt();
            if (b == null &&
                c == null &&
                preset == null &&
                r == null &&
                g == null &&
                bl == null) {
              return _err(req, 400,
                  'Body needs at least one of: brightness, contrast (0-100), '
                  'colorPreset (5/6/8/11), redGain/greenGain/blueGain (0-100).');
            }
            if (b != null) await DdcService.setBrightness(id, b);
            if (c != null) await DdcService.setContrast(id, c);
            if (preset != null) await DdcService.setColorPreset(id, preset);
            if (r != null) {
              await DdcService.setUserGain(id, Vcp.redGain, r);
            }
            if (g != null) {
              await DdcService.setUserGain(id, Vcp.greenGain, g);
            }
            if (bl != null) {
              await DdcService.setUserGain(id, Vcp.blueGain, bl);
            }
            final m = await _find(id);
            return _ok(req, m.toJson());
          }
        }
        return _err(req, 404, 'Unknown monitors route.');
      }
      if (seg.length == 3 &&
          seg[0] == 'v1' &&
          seg[1] == 'presets' &&
          req.method == 'POST') {
        final name = seg[2].toLowerCase();
        final results = await DdcService.applyPreset(name);
        return _ok(req, {
          'preset': name,
          'brightness': LuxPresets.valueOf(name),
          'perMonitor': results.map((k, v) =>
              MapEntry('$k', v == null ? 'ok' : 'error: $v')),
        });
      }
      if (seg.length == 2 &&
          seg[0] == 'v1' &&
          seg[1] == 'profiles' &&
          req.method == 'GET') {
        return _ok(
            req, ColorProfiles.all.map((p) => p.toJson()).toList());
      }
      if (seg.length == 2 &&
          seg[0] == 'v1' &&
          seg[1] == 'tones' &&
          req.method == 'GET') {
        return _ok(req, HwTones.all.map((t) => t.toJson()).toList());
      }
      if (seg.length == 3 &&
          seg[0] == 'v1' &&
          seg[1] == 'tones' &&
          req.method == 'POST') {
        final tone = HwTones.byName(seg[2].toLowerCase());
        if (tone == null) {
          return _err(req, 400,
              'Unknown tone. Valid: ${HwTones.validNames}.');
        }
        final monitors = await DdcService.detect(withLevels: false);
        final perMonitor = <String, String>{};
        for (final m in monitors) {
          try {
            await DdcService.setColorPreset(m.id, tone.preset14);
            perMonitor['${m.id}'] = 'ok';
          } on LuxException catch (e) {
            perMonitor['${m.id}'] = 'error: ${e.message}';
          }
        }
        return _ok(req, {'tone': tone.name, 'perMonitor': perMonitor});
      }
      if (seg.length == 3 &&
          seg[0] == 'v1' &&
          seg[1] == 'color' &&
          req.method == 'GET') {
        final id = int.tryParse(seg[2]);
        if (id == null) return _err(req, 400, 'Invalid monitor id.');
        final preset = await DdcService.getColorPreset(id);
        final gains = await DdcService.getRgbGains(id);
        return _ok(req, {
          'id': id,
          'colorPreset': '0x${preset.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          'redGain': gains.r,
          'greenGain': gains.g,
          'blueGain': gains.b,
        });
      }
      if (seg.length == 3 &&
          seg[0] == 'v1' &&
          seg[1] == 'profiles' &&
          req.method == 'POST') {
        final result =
            await ColorService.applyProfile(seg[2].toLowerCase());
        return _ok(req, result);
      }
      if (seg.length == 2 &&
          seg[0] == 'v1' &&
          seg[1] == 'temperature' &&
          req.method == 'DELETE') {
        await ColorService.clearTemperature();
        return _ok(req, {'restored': true});
      }
      return _err(req, 404, 'Unknown route. See GET /v1/skill.');
    } on LuxException catch (e) {
      return _err(req, 422, e.message);
    } catch (e) {
      return _err(req, 500, 'Internal error: $e');
    }
  }

  bool _authorized(HttpRequest req) {
    final header = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final m = RegExp(r'^Bearer\s+(\S+)$').firstMatch(header.trim());
    return m != null && m.group(1) == token;
  }

  Future<Map<String, dynamic>> _jsonBody(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const LuxException('Body must be a JSON object.');
    }
    return decoded;
  }

  Future<MonitorInfo> _find(int id) async {
    final monitors = await DdcService.detect();
    try {
      return monitors.firstWhere((m) => m.id == id);
    } on StateError {
      throw LuxException('No monitor with id $id.');
    }
  }

  Map<String, dynamic> _skillJson() => {
        'name': 'lux-control',
        'auth': 'Authorization: Bearer <token from ~/.config/lux/token>',
        'base': 'http://127.0.0.1:$port/v1',
        'examples': {
          'list': 'GET /v1/monitors',
          'dim': 'PUT /v1/monitors/1 {"brightness": 20}',
          'night': 'POST /v1/presets/night',
          'profiles': 'GET /v1/profiles',
          'gaming': 'POST /v1/profiles/gaming',
          'restore_color': 'DELETE /v1/temperature',
        },
        'vcp': {'brightness': '0x10 (0-100)', 'contrast': '0x12 (0-100)'},
        'cli_fallback':
            'scripts/luxctl (works even when the app is closed)',
      };

  void _ok(HttpRequest req, Object data) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonOk(data))
      ..close();
  }

  void _err(HttpRequest req, int code, String message) {
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonErr(message, code))
      ..close();
  }
}
