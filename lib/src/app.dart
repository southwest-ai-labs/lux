import 'dart:ui';

import 'package:flutter/material.dart';

import 'color_service.dart';
import 'ddc_service.dart';
import 'glass_card.dart';
import 'models.dart';
import 'profiles_section.dart';
import 'tones_section.dart';

class LuxApp extends StatelessWidget {
  final Future<void> Function() onHide;
  final Future<void> Function() onQuit;

  const LuxApp({super.key, required this.onHide, required this.onQuit});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        cardTheme: const CardThemeData(
          color: Color(0x141C1C22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0x38FFFFFF)),
          ),
          elevation: 8,
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: HomePage(onHide: onHide, onQuit: onQuit),
    );
  }
}

class HomePage extends StatefulWidget {
  final Future<void> Function() onHide;
  final Future<void> Function() onQuit;

  const HomePage({super.key, required this.onHide, required this.onQuit});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<MonitorInfo>? _monitors;
  String? _error;
  bool _loading = true;
  bool _applyingPreset = false;
  String? _activeProfile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final monitors = await DdcService.detect();
      if (!mounted) return;
      setState(() {
        _monitors = monitors;
        _error = monitors.isEmpty ? 'No DDC/CI monitors detected.' : null;
      });
    } on LuxException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _applyingPreset = false;
        });
      }
    }
  }

  Future<void> _applyPreset(String name) async {
    setState(() => _applyingPreset = true);
    try {
      final results = await DdcService.applyPreset(name);
      final failures =
          results.entries.where((e) => e.value != null).toList();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failures.isEmpty
            ? '$name applied to ${results.length} monitor(s).'
            : '${failures.length} monitor(s) failed: ${failures.first.value}'),
      ));
      await _reload();
    } on LuxException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _applyingPreset = false);
    }
  }

  Future<void> _applyProfile(String name) async {
    setState(() {
      _applyingPreset = true;
      _activeProfile = null;
    });
    try {
      final res = await ColorService.applyProfile(name);
      if (!mounted) return;
      final bErr =
          (res['brightness'] as Map)['error'] as String?;
      final tErr =
          (res['temperature'] as Map)['error'] as String?;
      final parts = <String>[];
      if (bErr != null) parts.add('brillo no aplicado ($bErr)');
      if (tErr != null) parts.add('color no aplicado ($tErr)');
      setState(() => _activeProfile = name);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(parts.isEmpty
            ? 'Perfil $name aplicado (brillo + color).'
            : 'Perfil $name parcial: ${parts.join(' · ')}'),
      ));
      await _reload();
    } on LuxException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _restoreColor() async {
    await ColorService.clearTemperature();
    if (!mounted) return;
    setState(() => _activeProfile = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Color restaurado (tu night-light previo).')));
  }

  /// Runs [action] showing errors in a snackbar. For fire-and-forget
  /// child sections (tones) that manage their own refresh.
  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
    } on LuxException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Frosted-glass over an internal aurora backdrop: the Linux embedder
    // surface is opaque (window_manager only tints GTK CSS), so cards blur
    // this painted backdrop instead of the desktop. Bounded, cheap, real.
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                // Translucent: the real desktop shows through softly
                // (the runner now provides a true RGBA surface).
                colors: [Color(0xB31A1410), Color(0xB30D0B09)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.22),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -70,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.teal.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
        Scaffold(
      appBar: AppBar(
        title: const Text('Lux — Monitor brightness'),
        actions: [
          IconButton(
            tooltip: 'Re-read monitors',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
          IconButton(
            tooltip: 'Hide to tray',
            icon: const Icon(Icons.visibility_off),
            onPressed: () => widget.onHide(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) _ErrorCard(message: _error!),
                _PresetRow(
                  busy: _applyingPreset,
                  onPreset: _applyPreset,
                ),
                const SizedBox(height: 8),
                ProfilesSection(
                  active: _activeProfile,
                  busy: _applyingPreset,
                  onApply: _applyProfile,
                  onRestore: _restoreColor,
                ),
                const SizedBox(height: 8),
                if (_monitors != null && _monitors!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: GlassCard(
                      child: TonesSection(
                        monitorId: _monitors!.first.id,
                        busy: _applyingPreset,
                        runGuarded: _runGuarded,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_monitors != null)
                  for (final m in _monitors!)
                    _MonitorCard(
                      key: ValueKey(m.id),
                      monitor: m,
                      onChanged: (updated) {
                        setState(() {
                          _monitors = _monitors!
                              .map((x) => x.id == updated.id ? updated : x)
                              .toList();
                        });
                      },
                    ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Quit Lux'),
                  onPressed: () => widget.onQuit(),
                ),
              ],
            ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  final bool busy;
  final Future<void> Function(String) onPreset;

  const _PresetRow({required this.busy, required this.onPreset});

  @override
  Widget build(BuildContext context) {
    ButtonSegment<String> seg(String v, String label, IconData icon) =>
        ButtonSegment(value: v, label: Text(label), icon: Icon(icon));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Presets (all monitors)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: [
            seg('night', 'Night 15%', Icons.bedtime),
            seg('reading', 'Reading 35%', Icons.menu_book),
            seg('day', 'Day 80%', Icons.wb_sunny),
          ],
          selected: const {},
          onSelectionChanged: busy ? null : (s) async {
            if (s.isNotEmpty) await onPreset(s.first);
          },
        ),
      ],
    );
  }
}

class _MonitorCard extends StatefulWidget {
  final MonitorInfo monitor;
  final void Function(MonitorInfo) onChanged;

  const _MonitorCard({super.key, required this.monitor, required this.onChanged});

  @override
  State<_MonitorCard> createState() => _MonitorCardState();
}

class _MonitorCardState extends State<_MonitorCard> {
  late double _brightness;
  late double _contrast;

  @override
  void initState() {
    super.initState();
    _brightness = (widget.monitor.brightness ?? 50).toDouble();
    _contrast = (widget.monitor.contrast ?? 70).toDouble();
  }

  @override
  void didUpdateWidget(covariant _MonitorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monitor.brightness != widget.monitor.brightness ||
        oldWidget.monitor.contrast != widget.monitor.contrast) {
      _brightness = (widget.monitor.brightness ?? 50).toDouble();
      _contrast = (widget.monitor.contrast ?? 70).toDouble();
    }
  }

  Future<void> _commitBrightness(double v) async {
    try {
      await DdcService.setBrightness(widget.monitor.id, v.round());
      widget.onChanged(
          widget.monitor.copyWith(brightness: v.round()));
    } on LuxException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _commitContrast(double v) async {
    try {
      await DdcService.setContrast(widget.monitor.id, v.round());
      widget.onChanged(widget.monitor.copyWith(contrast: v.round()));
    } on LuxException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.monitor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${m.label}  ·  ${m.drm}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.brightness_6, size: 18),
                Expanded(
                  child: Slider(
                    value: _brightness.clamp(0, 100),
                    max: 100,
                    divisions: 100,
                    label: '${_brightness.round()}%',
                    onChanged: m.brightness == null
                        ? null
                        : (v) => setState(() => _brightness = v),
                    onChangeEnd: _commitBrightness,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text('${_brightness.round()}%',
                      textAlign: TextAlign.end),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.contrast, size: 18),
                Expanded(
                  child: Slider(
                    value: _contrast.clamp(0, 100),
                    max: 100,
                    divisions: 100,
                    label: '${_contrast.round()}%',
                    onChanged: m.contrast == null
                        ? null
                        : (v) => setState(() => _contrast = v),
                    onChangeEnd: _commitContrast,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child:
                      Text('${_contrast.round()}%', textAlign: TextAlign.end),
                ),
              ],
            ),
            if (m.brightness == null || m.contrast == null)
              Text(
                'Some levels are unreadable on this panel — sliders still send values.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  bool get _isI2c =>
      message.contains('/dev/i2c') || message.contains('Permission denied');

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cannot reach monitors',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(message),
            if (_isI2c) ...[
              const SizedBox(height: 8),
              const SelectableText(
                'NixOS fix:\n'
                '  hardware.i2c.enable = true;\n'
                '  users.users.<you>.extraGroups = [ "i2c" ];\n'
                '  environment.systemPackages = [ pkgs.ddcutil ];\n'
                'Then: sudo nixos-rebuild switch --flake /etc/nixos#swal, relogin.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
