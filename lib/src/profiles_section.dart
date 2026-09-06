import 'package:flutter/material.dart';

import 'models.dart';

/// Profile picker: Jugar / Programar / Videos / Leer.
/// Color (software) works immediately; brightness (hardware) joins in
/// once DDC/CI is reachable — the applied message says which parts landed.
class ProfilesSection extends StatelessWidget {
  final String? active;
  final bool busy;
  final Future<void> Function(String) onApply;
  final Future<void> Function() onRestore;

  const ProfilesSection({
    super.key,
    this.active,
    required this.busy,
    required this.onApply,
    required this.onRestore,
  });

  IconData _icon(String name) => switch (name) {
        'gaming' => Icons.sports_esports,
        'code' => Icons.code,
        'video' => Icons.movie,
        _ => Icons.menu_book,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Perfiles', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in ColorProfiles.all)
              FilterChip(
                selected: active == p.name,
                showCheckmark: false,
                avatar: Icon(_icon(p.name), size: 18),
                label: Text('${p.label} · ${p.temperature}K'),
                tooltip: p.description,
                onSelected: busy ? null : (_) => onApply(p.name),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Color por software: inmediato. Brillo por hardware: '
                'requiere i2c.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => onRestore(),
              child: const Text('Restaurar color'),
            ),
          ],
        ),
      ],
    );
  }
}
