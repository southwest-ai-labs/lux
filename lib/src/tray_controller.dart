import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'color_service.dart';
import 'ddc_service.dart';
import 'models.dart';

/// System-tray icon + context menu. The app lives here; the window is
/// secondary (shown on demand, hidden on close).
class LuxTray with TrayListener {
  final Future<void> Function() onToggleWindow;
  final Future<void> Function() onShowWindow;
  final Future<void> Function() onQuit;
  final Future<void> Function()? onChanged;

  bool _ready = false;

  LuxTray({
    required this.onToggleWindow,
    required this.onShowWindow,
    required this.onQuit,
    this.onChanged,
  });

  /// Best-effort init: a missing tray (no StatusNotifier host) must not
  /// prevent the app window from working.
  Future<void> initSafe() async {
    try {
      await trayManager.setIcon('assets/tray_icon.png');
      await trayManager.setToolTip('Lux — monitor brightness');
      await refreshMenu();
      trayManager.addListener(this);
      _ready = true;
    } catch (e) {
      debugPrint('lux: tray unavailable: $e');
    }
  }

  Future<void> refreshMenu({String? status}) async {
    if (!_ready) return;
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'toggle', label: 'Show / Hide Lux'),
        MenuItem.separator(),
        MenuItem(key: 'preset_night', label: 'Night (15%)'),
        MenuItem(key: 'preset_reading', label: 'Reading (35%)'),
        MenuItem(key: 'preset_day', label: 'Day (80%)'),
        MenuItem.separator(),
        MenuItem(key: 'profile_gaming', label: 'Perfil: Jugar'),
        MenuItem(key: 'profile_code', label: 'Perfil: Programar'),
        MenuItem(key: 'profile_video', label: 'Perfil: Videos'),
        MenuItem(key: 'profile_read', label: 'Perfil: Leer'),
        MenuItem(key: 'color_restore', label: 'Restaurar color'),
        MenuItem.separator(),
        MenuItem(
          key: 'refresh',
          label: status ?? 'Re-read monitors',
          disabled: status != null,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit Lux'),
      ]));
    } catch (e) {
      debugPrint('lux: tray menu failed: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    // Single left-click = open the window on top. (Right-click opens the
    // native context menu via the tray host; double-click just toggled
    // show/hide which looked broken.)
    onShowWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final key = menuItem.key ?? '';
    if (key.startsWith('profile_')) {
      try {
        await ColorService.applyProfile(key.substring('profile_'.length));
      } on LuxException catch (e) {
        debugPrint('lux: profile failed: $e');
      }
      await onChanged?.call();
      return;
    }
    switch (menuItem.key) {
      case 'toggle':
        await onToggleWindow();
      case 'preset_night':
      case 'preset_reading':
      case 'preset_day':
        final name = menuItem.key!.split('_').last;
        try {
          await DdcService.applyPreset(name);
          await refreshMenu();
        } on LuxException catch (e) {
          debugPrint('lux: preset failed: $e');
        }
        await onChanged?.call();
      case 'color_restore':
        await ColorService.clearTemperature();
        await onChanged?.call();
      case 'refresh':
        await onChanged?.call();
      case 'quit':
        await onQuit();
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (e) {
      debugPrint('lux: tray destroy failed: $e');
    }
  }
}
