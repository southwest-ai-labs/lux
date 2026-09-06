import 'package:flutter/material.dart';

import 'ddc_service.dart';
import 'models.dart';

/// Hardware tones from the panel's own presets (VCP 0x14) + RGB gains.
/// These run in the monitor: zero overhead, fullscreen-proof.
/// Calidez (<6500K) no existe en hardware: ver Perfiles (shaders).
class TonesSection extends StatefulWidget {
  final int monitorId;
  final bool busy;
  final Future<void> Function(Future<void> Function()) runGuarded;

  const TonesSection({
    super.key,
    required this.monitorId,
    required this.busy,
    required this.runGuarded,
  });

  @override
  State<TonesSection> createState() => _TonesSectionState();
}

class _TonesSectionState extends State<TonesSection> {
  int? _preset;
  double _r = 50, _g = 50, _b = 50;
  bool _gainsKnown = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final preset = await DdcService.getColorPreset(widget.monitorId);
      final gains = await DdcService.getRgbGains(widget.monitorId);
      if (!mounted) return;
      setState(() {
        _preset = preset;
        _r = gains.r.toDouble();
        _g = gains.g.toDouble();
        _b = gains.b.toDouble();
        _gainsKnown = true;
      });
    } on LuxException {
      // Unreadable panel: sliders still send values.
    }
  }

  Future<void> _applyTone(HwTone tone) async {
    await widget.runGuarded(() async {
      await DdcService.setColorPreset(widget.monitorId, tone.preset14);
      await _read();
    });
  }

  Future<void> _commitGain(int channel, double v) async {
    await widget.runGuarded(() async {
      await DdcService.setUserGain(widget.monitorId, channel, v.round());
      await _read();
    });
  }

  Widget _gainRow(
      String label, IconData icon, double value, ValueChanged<double> onEnd) {
    return Row(
      children: [
        Icon(icon, size: 18),
        Expanded(
          child: Slider(
            value: value.clamp(0, 100),
            max: 100,
            divisions: 100,
            label: '${value.round()}',
            onChanged: _gainsKnown ? (v) => setState(() {
              if (label == 'R') _r = v;
              if (label == 'G') _g = v;
              if (label == 'B') _b = v;
            }) : null,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(width: 40, child: Text('${value.round()}', textAlign: TextAlign.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tonalidades hardware',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in HwTones.all)
              FilterChip(
                selected: _preset == t.preset14,
                showCheckmark: false,
                label: Text(t.label),
                tooltip: t.description,
                onSelected:
                    widget.busy ? null : (_) => _applyTone(t),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _gainRow('R', Icons.circle, _r,
            (v) => _commitGain(Vcp.redGain, v)),
        _gainRow('G', Icons.circle_outlined, _g,
            (v) => _commitGain(Vcp.greenGain, v)),
        _gainRow('B', Icons.water_drop, _b,
            (v) => _commitGain(Vcp.blueGain, v)),
        Text(
          'Mover RGB cambia a modo Usuario automáticamente.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
