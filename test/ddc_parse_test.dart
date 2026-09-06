import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/ddc_service.dart';
import 'package:lux/src/models.dart';

const _sampleDetect = '''
Display 1
   I2C bus:  /dev/i2c-5
   DRM connector:  card1-DP-2
   Monitor:  AOC:24G42HE:204RCUA000166

Display 2
   I2C bus:  /dev/i2c-6
   DRM connector:  card1-HDMI-A-1
   Mfg id:  DEL
   Model:  P2419H
   Serial number:  ABC123
''';

void main() {
  group('parseDetect', () {
    test('parses packed Monitor line and EDID fields', () {
      final monitors = DdcService.parseDetect(_sampleDetect);
      expect(monitors, hasLength(2));

      expect(monitors[0].id, 1);
      expect(monitors[0].drm, 'card1-DP-2');
      expect(monitors[0].make, 'AOC');
      expect(monitors[0].model, '24G42HE');
      expect(monitors[0].serial, '204RCUA000166');

      expect(monitors[1].id, 2);
      expect(monitors[1].make, 'DEL');
      expect(monitors[1].model, 'P2419H');
      expect(monitors[1].serial, 'ABC123');
    });

    test('empty output yields empty list (never throws)', () {
      expect(DdcService.parseDetect(''), isEmpty);
      expect(DdcService.parseDetect('No displays found'), isEmpty);
    });

    test('missing fields fall back, never throw', () {
      final monitors = DdcService.parseDetect('Display 7\n   I2C bus: /dev/i2c-9\n');
      expect(monitors, hasLength(1));
      expect(monitors[0].make, 'Unknown');
      expect(monitors[0].toJson()['id'], 7);
    });
  });

  group('parseGetvcpBrief', () {
    test('parses "VCP 10 C 45 100"', () {
      final r = DdcService.parseGetvcpBrief('VCP 10 C 45 100', Vcp.brightness);
      expect(r.current, 45);
      expect(r.max, 100);
    });

    test('unsupported feature throws LuxException', () {
      expect(
        () => DdcService.parseGetvcpBrief('VCP 10 C 45 100', Vcp.contrast),
        throwsA(isA<LuxException>()),
      );
      expect(
        () => DdcService.parseGetvcpBrief('garbage', Vcp.brightness),
        throwsA(isA<LuxException>()),
      );
    });
  });

  group('LuxPresets', () {
    test('known presets in range', () {
      for (final name in ['night', 'reading', 'day']) {
        expect(LuxPresets.contains(name), isTrue);
        expect(LuxPresets.valueOf(name), inInclusiveRange(0, 100));
      }
      expect(LuxPresets.contains('supernova'), isFalse);
    });
  });

  group('extra controls (verified live on AOC)', () {
    test('input allowlist = capabilities values only', () {
      expect(DdcService.inputSourcesAllowed, {0x0F, 0x11});
    });

    test('input rejects anything else (signal-loss guard)', () async {
      for (final bad in [0x01, 0x03, 0x04, 0x10, 0x12, 0x60, 99]) {
        await expectLater(
          DdcService.setInputSource(1, bad),
          throwsA(isA<LuxException>()),
        );
      }
    });

    test('parse single-NC brief', () {
      expect(DdcService.parseSingleNcBrief('VCP 60 SNC x0f', 0x60), 0x0F);
      expect(DdcService.parseSingleNcBrief('VCP D6 SNC x01', 0xD6), 0x01);
      expect(
        () => DdcService.parseSingleNcBrief('garbage', 0x60),
        throwsA(isA<LuxException>()),
      );
    });
  });
}
