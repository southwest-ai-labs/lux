import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/tray_controller.dart';

void main() {
  group('LuxMenu model (pure, no bus)', () {
    test('actionable ids are unique', () {
      final ids = LuxMenu.actionable.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('expected actions exist', () {
      final ids = LuxMenu.actionable.map((e) => e.id).toSet();
      expect(ids, containsAll([1, 10, 11, 12, 20, 21, 22, 23, 24, 30, 31, 32, 40]));
    });

    test('labels non-empty, separators unlabeled', () {
      for (final e in LuxMenu.entries) {
        if (e.separator) {
          expect(e.label, isEmpty);
        } else {
          expect(e.label, isNotEmpty);
        }
      }
    });
  });
}
