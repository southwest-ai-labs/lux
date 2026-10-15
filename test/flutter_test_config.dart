import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Runs before every test file.
///
/// `flutter test` builds the fonts declared in pubspec.yaml (MaterialIcons)
/// into build/unit_test_assets, but does not register them. Without this,
/// icons render as placeholder boxes, including in golden screenshots.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final manifest = File('build/unit_test_assets/FontManifest.json');
  if (!manifest.existsSync()) {
    throw StateError(
        'Missing ${manifest.path}. Run tests through `flutter test`.');
  }
  for (final entry in jsonDecode(manifest.readAsStringSync()) as List) {
    final family = entry as Map<String, dynamic>;
    final loader = FontLoader(family['family'] as String);
    for (final font in family['fonts'] as List) {
      final asset = (font as Map<String, dynamic>)['asset'] as String;
      final bytes = File('build/unit_test_assets/$asset').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    }
    await loader.load();
  }
  await testMain();
}
