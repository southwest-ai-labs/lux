import 'dart:io';

import 'package:lux/src/process_runner.dart';

/// Stands in for `ddcutil` and `hyprshade` during tests.
///
/// Replies mirror the AOC 24G42HE read on the real machine. Every command is
/// recorded, so a test can assert exactly what would have reached the panel,
/// and in particular that opening the app only ever reads from it.
class FakeShell {
  FakeShell({this.ddcInstalled = true});

  /// When false, `ddcutil` is reported missing from PATH.
  final bool ddcInstalled;

  final List<String> _calls = [];

  /// Every command issued so far, e.g. `ddcutil --display 1 setvcp 10 15`.
  List<String> get calls => List.unmodifiable(_calls);

  /// Only the commands that write to the panel or the compositor.
  List<String> get writes => _calls
      .where((c) => c.contains(' setvcp ') || c.startsWith('hyprshade '))
      .toList();

  /// Route all Lux process calls through this fake.
  void install() => Shell.run = _run;

  /// Restore the real process runner.
  void uninstall() => Shell.run = Process.run;

  Future<ProcessResult> _run(String executable, List<String> args) async {
    _calls.add('$executable ${args.join(' ')}');
    switch (executable) {
      case 'which':
        return ProcessResult(1, 0, '/run/current-system/sw/bin/$executable', '');
      case 'hyprshade':
        return ProcessResult(2, 0, '', '');
      case 'ddcutil':
        return _ddcutil(args);
      default:
        return ProcessResult(3, 127, '', '$executable: not faked');
    }
  }

  ProcessResult _ddcutil(List<String> args) {
    if (!ddcInstalled) {
      throw const ProcessException('ddcutil', [], 'No such file or directory');
    }
    if (args.contains('--version')) {
      return ProcessResult(10, 0, 'ddcutil 2.2.0', '');
    }
    if (args.contains('detect')) {
      return ProcessResult(11, 0, _detectOutput, '');
    }
    if (args.contains('getvcp')) {
      final reply = _vcpReplies[args.last.toUpperCase()];
      if (reply == null) {
        return ProcessResult(
            12, 1, '', 'Unsupported feature code ${args.last}');
      }
      return ProcessResult(12, 0, '$reply\n', '');
    }
    if (args.contains('setvcp')) {
      return ProcessResult(13, 0, '', '');
    }
    return ProcessResult(14, 1, '', 'ddcutil: unexpected arguments $args');
  }

  static const _detectOutput = '''
Display 1
   DRM connector:           card1-DP-1
   Mfg id:                  AOC
   Model:                   24G42HE
   Serial number:           FAKE0000001
''';

  /// Brief `getvcp` replies keyed by hex VCP code, without the 0x prefix.
  static const _vcpReplies = {
    '10': 'VCP 10 C 45 100', // brightness
    '12': 'VCP 12 C 70 100', // contrast
    '14': 'VCP 14 CNC x05', // colour preset (6500K)
    '16': 'VCP 16 C 100 100', // red gain
    '18': 'VCP 18 C 96 100', // green gain
    '1A': 'VCP 1A C 88 100', // blue gain
    '60': 'VCP 60 SNC x0f', // input: DP-1
    '62': 'VCP 62 C 95 100', // volume
    'D6': 'VCP D6 SNC x01', // power: on
  };
}
