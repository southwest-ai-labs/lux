import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/color_service.dart';
import 'src/ddc_service.dart';
import 'src/tray_controller.dart';

/// Hide instead of quitting when the window close button is pressed —
/// the app lives in the system tray.
class _WindowHandler with WindowListener {
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await _hideWindow();
    }
  }
}

Future<void> _toggleWindow() async {
  if (await windowManager.isVisible()) {
    await _hideWindow();
  } else {
    await _showWindow();
  }
}

/// Open centered, focused and above all Hyprland windows.
Future<void> _showWindow() async {
  await windowManager.show();
  await windowManager.center();
  await windowManager.focus();
  await windowManager.setAlwaysOnTop(true);
}

Future<void> _hideWindow() async {
  await windowManager.setAlwaysOnTop(false);
  await windowManager.hide();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Floating glass panel: no system frame, transparent canvas so the
  // BackdropFilter samples the real desktop (Hyprland layerrule blur
  // enhances it further). Move with Super+drag.
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);

  await windowManager.setPreventClose(true);
  await windowManager.setTitle('Lux — Monitor Brightness');
  await windowManager.setSize(const Size(560, 700));
  windowManager.addListener(_WindowHandler());

  LuxTray? tray;
  tray = LuxTray(
    onToggleWindow: _toggleWindow,
    onShowWindow: _showWindow,
    onQuit: () async {
      await tray?.dispose();
      await ColorService.shutdown();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    },
  );
  await tray.initSafe();

  runApp(LuxApp(
    onHide: _hideWindow,
    onQuit: () async {
      await tray?.dispose();
      await ColorService.shutdown();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    },
  ));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await windowManager.waitUntilReadyToShow();
    await windowManager.show();
    await windowManager.focus();
    // Warm the tray menu; failures are already handled inside DdcService.
    try {
      await DdcService.isAvailable;
    } catch (_) {}
  });
}
