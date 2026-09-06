import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/ddc_service.dart';
import 'package:lux/src/models.dart';

void main() {
  group('HwTones table', () {
    test('three hardware tones from panel capabilities', () {
      expect(HwTones.all, hasLength(3));
      expect(
        HwTones.all.map((t) => t.preset14),
        containsAll([0x05, 0x06, 0x08]),
      );
    });

    test('aliases resolve (es/en)', () {
      expect(HwTones.byName('srgb')?.preset14, 0x05);
      expect(HwTones.byName('6500')?.preset14, 0x05);
      expect(HwTones.byName('frio75')?.preset14, 0x06);
      expect(HwTones.byName('9300')?.preset14, 0x08);
      expect(HwTones.byName('oled'), isNull);
    });
  });

  group('color preset guards', () {
    test('allowlist holds exactly the panel values', () {
      expect(DdcService.colorPresetsAllowed, {0x05, 0x06, 0x08, 0x0B});
    });

    test('dangerous codes are rejected (never touch hardware)', () async {
      // NOTE: 0x05/0x06/0x08/0x0B are the panel's real presets (allowed),
      // so they must NOT appear here — the guard must throw before any
      // I2C traffic for everything else.
      for (final bad in [0x60, 0x04, 0x02, 0x00, 0x14, 0xE0, 99, 255]) {
        await expectLater(
          DdcService.setColorPreset(1, bad),
          throwsA(isA<LuxException>()),
        );
      }
    });

    test('gain channels restricted to RGB', () async {
      await expectLater(
        DdcService.setUserGain(1, 0x60, 50),
        throwsA(isA<LuxException>()),
      );
      await expectLater(
        DdcService.setUserGain(1, 0x10, 50),
        throwsA(isA<LuxException>()),
      );
    });

    test('parse NC brief (current = last hex token)', () {
      expect(
        DdcService.parseColorPresetBrief('VCP 14 CNC x00 x0b x00 x06'),
        0x06,
      );
      expect(
        DdcService.parseColorPresetBrief('VCP 14 CNC x00 x0b x00 x05\n'),
        0x05,
      );
      expect(
        () => DdcService.parseColorPresetBrief('garbage'),
        throwsA(isA<LuxException>()),
      );
    });
  });
}
