import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lux/src/glass_card.dart';

void main() {
  testWidgets('GlassCard renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassCard(child: Text('frosted')),
        ),
      ),
    );
    expect(find.text('frosted'), findsOneWidget);
  });
}
