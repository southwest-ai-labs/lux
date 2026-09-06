import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/api_server.dart';
import 'src/app.dart';
import 'src/ddc_service.dart';
import 'src/tray_controller.dart';

/// Hide instead of quitting when the window close button is pressed —
/// the app lives in the system tray.
class _WindowHandler with WindowListener {
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}

Future<void> _toggleWindow() async {
  if (await windowManager.isVisible()) {
    await windowManager.hide();
  } else {
    await windowManager.show();
    await windowManager.focus();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await windowManager.setPreventClose(true);
  await windowManager.setTitle('Lux — Monitor Brightness');
  await windowManager.setSize(const Size(560, 700));
  windowManager.addListener(_WindowHandler());

  // Local agent API (loopback only). Null when another instance owns it.
  final api = await LuxApiServer.tryStart();

  LuxTray? tray;
  tray = LuxTray(
    onToggleWindow: _toggleWindow,
    onQuit: () async {
      await tray?.dispose();
      await api?.stop();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    },
  );
  await tray.initSafe();

  runApp(LuxApp(
    api: api,
    onHide: () => windowManager.hide(),
    onQuit: () async {
      await tray?.dispose();
      await api?.stop();
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
