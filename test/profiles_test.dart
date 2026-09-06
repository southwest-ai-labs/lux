import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/color_service.dart';
import 'package:lux/src/models.dart';

void main() {
  group('ColorProfiles table', () {
    test('four profiles with sane ranges', () {
      expect(ColorProfiles.all, hasLength(4));
      for (final p in ColorProfiles.all) {
        expect(p.brightness, inInclusiveRange(0, 100),
            reason: '${p.name} brightness');
        expect(p.temperature, inInclusiveRange(1000, 10000),
            reason: '${p.name} temperature');
        expect(p.label, isNotEmpty);
      }
    });

    test('spanish + english aliases resolve', () {
      expect(ColorProfiles.byName('jugar')?.name, 'gaming');
      expect(ColorProfiles.byName('GAMING')?.name, 'gaming');
      expect(ColorProfiles.byName('programar')?.name, 'code');
      expect(ColorProfiles.byName('cine')?.name, 'video');
      expect(ColorProfiles.byName('pelis')?.name, 'video');
      expect(ColorProfiles.byName('leer')?.name, 'read');
      expect(ColorProfiles.byName('lectura')?.name, 'read');
      expect(ColorProfiles.byName('  Video  ')?.name, 'video');
    });

    test('unknown names yield null', () {
      expect(ColorProfiles.byName('supernova'), isNull);
      expect(ColorProfiles.byName(''), isNull);
    });

    test('toJson carries hardware + software parts', () {
      final j = ColorProfiles.read.toJson();
      expect(j['brightness'], 35);
      expect(j['temperature'], 4000);
    });
  });

  group('ColorService helpers (pure)', () {
    test('argsForTemp pins both ends (K-1/K, wlsunset needs high>low)', () {
      expect(ColorService.argsForTemp(4500), ['-t', '4499', '-T', '4500']);
    });

    test('isValidTemp boundaries', () {
      expect(ColorService.isValidTemp(999), isFalse);
      expect(ColorService.isValidTemp(1000), isTrue);
      expect(ColorService.isValidTemp(10000), isTrue);
      expect(ColorService.isValidTemp(10001), isFalse);
    });
  });
}
