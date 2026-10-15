import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/app.dart';
import 'package:lux/src/models.dart';

import '../support/fake_shell.dart';

/// Same size main.dart gives the real window.
const _windowSize = Size(560, 700);

/// Headless end-to-end suite: the full LuxApp runs against [FakeShell], so no
/// test needs a monitor, I2C, or a Wayland compositor. The screenshots in
/// docs/screenshots are golden files: they fail the suite when the UI drifts,
/// and `flutter test --update-goldens test/e2e` regenerates them.
Future<void> _loadTestFont() async {
  // DejaVu Sans stands in for the Roboto default so the screenshots do not
  // depend on whatever fonts the machine running the suite has installed.
  final bytes = File('test/fixtures/fonts/DejaVuSans.ttf').readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<FakeShell> _launch(WidgetTester tester,
    {bool ddcInstalled = true}) async {
  final shell = FakeShell(ddcInstalled: ddcInstalled)..install();
  addTearDown(shell.uninstall);

  // Render at 2x so the PNGs keep text sharp.
  tester.view.physicalSize = _windowSize * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(LuxApp(
    onHide: () async {},
    onQuit: () async {},
  ));
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  setUpAll(_loadTestFont);

  group('startup', () {
    testWidgets('reads the panel and shows its brightness', (tester) async {
      final shell = await _launch(tester);

      expect(find.textContaining('24G42HE'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(shell.writes, isEmpty,
          reason: 'opening Lux must only read from the panel');
    });

    testWidgets('reports a missing ddcutil instead of crashing',
        (tester) async {
      await _launch(tester, ddcInstalled: false);

      expect(find.text('Cannot reach monitors'), findsOneWidget);
      expect(find.textContaining('ddcutil not found in PATH'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('night preset sends brightness 15 to the monitor',
        (tester) async {
      final shell = await _launch(tester);

      await tester.tap(find.text('Night 15%'));
      await tester.pumpAndSettle();

      expect(shell.writes, contains('ddcutil --display 1 setvcp 10 15'));
    });

    testWidgets('applying a profile activates its hyprshade shader',
        (tester) async {
      final shell = await _launch(tester);
      final reading = ColorProfiles.byName('read')!;

      await tester.tap(find.textContaining(reading.label));
      await tester.pumpAndSettle();

      expect(shell.writes, contains('hyprshade on lux-read'));
    });

    testWidgets('normal use never writes input, power or colour codes',
        (tester) async {
      final shell = await _launch(tester);

      await tester.tap(find.text('Day 80%'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(ColorProfiles.byName('code')!.label));
      await tester.pumpAndSettle();

      final risky = shell.writes.where(
        (c) => c.contains('setvcp 60 ') || c.contains('setvcp D6 '),
      );
      expect(risky, isEmpty);
    });
  });

  group('screenshots', () {
    testWidgets('home', (tester) async {
      await _launch(tester);

      await expectLater(
        find.byType(LuxApp),
        matchesGoldenFile('../../docs/screenshots/home.png'),
      );
    });

    testWidgets('home scrolled to colour tones', (tester) async {
      await _launch(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(LuxApp),
        matchesGoldenFile('../../docs/screenshots/tones.png'),
      );
    });

    testWidgets('error state without ddcutil', (tester) async {
      await _launch(tester, ddcInstalled: false);

      await expectLater(
        find.byType(LuxApp),
        matchesGoldenFile('../../docs/screenshots/error.png'),
      );
    });
  });
}
