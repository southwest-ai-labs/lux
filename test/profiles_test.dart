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
    test('shaderFor maps profiles to lux shaders', () {
      expect(ColorService.shaderFor('read'), 'lux-read');
      expect(ColorService.onArgs('video'), ['on', 'lux-video']);
      expect(ColorService.offArgs, ['off']);
    });

    test('shaderForKelvin picks nearest (>=6000 = off)', () {
      expect(ColorService.shaderForKelvin(6500), 'off');
      expect(ColorService.shaderForKelvin(6000), 'off');
      expect(ColorService.shaderForKelvin(5500), 'lux-code');
      expect(ColorService.shaderForKelvin(5000), 'lux-code');
      expect(ColorService.shaderForKelvin(4500), 'lux-video');
      expect(ColorService.shaderForKelvin(4250), 'lux-video');
      expect(ColorService.shaderForKelvin(4000), 'lux-read');
    });
  });
}
