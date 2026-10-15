import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/ddc_service.dart';
import 'package:lux/src/models.dart';
import 'package:lux/src/process_runner.dart';

import 'support/fake_shell.dart';

/// Regression: Lux started by a launcher whose PATH lacks the NixOS profiles
/// reported "ddcutil not found in PATH" while ddcutil was installed.
void main() {
  late List<String> Function() originalDirs;

  setUp(() {
    originalDirs = Shell.fallbackDirs;
  });

  tearDown(() {
    Shell.fallbackDirs = originalDirs;
  });

  test('finds ddcutil in a fallback directory when PATH misses it', () async {
    final profile = Directory.systemTemp.createTempSync('lux-profile-');
    addTearDown(() => profile.deleteSync(recursive: true));
    File('${profile.path}/ddcutil').writeAsStringSync('');
    Shell.fallbackDirs = () => [profile.path];

    final shell = FakeShell(onPath: false)..install();
    addTearDown(shell.uninstall);

    final monitors = await DdcService.detect();

    expect(monitors, hasLength(1));
    expect(monitors.single.model, '24G42HE');
    expect(shell.calls, contains('ddcutil --brief detect'));
  });

  test('still reports a missing ddcutil when no directory has it', () async {
    Shell.fallbackDirs = () => const [];

    final shell = FakeShell(onPath: false)..install();
    addTearDown(shell.uninstall);

    await expectLater(
      DdcService.detect(),
      throwsA(isA<LuxException>().having(
        (e) => e.message,
        'message',
        contains('ddcutil not found in PATH'),
      )),
    );
  });
}
