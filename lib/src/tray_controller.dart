import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import 'color_service.dart';
import 'ddc_service.dart';
import 'models.dart';

/// Own StatusNotifierItem + dbusmenu server (Linux-only).
///
/// Replaces tray_manager, whose exported dbusmenu layout was EMPTY
/// (GetLayout = root without children, verified over D-Bus) and which
/// never delivered clicks to Dart on Linux. Waybar renders our layout
/// itself, so a correct model is all the host needs.
///
/// Menu ids: 1 toggle · 10-12 presets · 20-24 profiles · 30-32 tones ·
/// 40 quit. Separators carry no action.
class LuxMenuEntry {
  final int id;
  final String label;
  final bool separator;
  const LuxMenuEntry(this.id, this.label, {this.separator = false});
}

/// Pure menu model (unit-testable, no bus needed).
abstract final class LuxMenu {
  static const entries = [
    LuxMenuEntry(1, 'Mostrar / ocultar Lux'),
    LuxMenuEntry(0, '', separator: true),
    LuxMenuEntry(10, 'Noche (15%)'),
    LuxMenuEntry(11, 'Lectura (35%)'),
    LuxMenuEntry(12, 'Día (80%)'),
    LuxMenuEntry(0, '', separator: true),
    LuxMenuEntry(20, 'Perfil: Jugar'),
    LuxMenuEntry(21, 'Perfil: Programar'),
    LuxMenuEntry(22, 'Perfil: Videos'),
    LuxMenuEntry(23, 'Perfil: Leer'),
    LuxMenuEntry(24, 'Restaurar color'),
    LuxMenuEntry(0, '', separator: true),
    LuxMenuEntry(30, 'Tono: sRGB 6500K'),
    LuxMenuEntry(31, 'Tono: Frío 7500K'),
    LuxMenuEntry(32, 'Tono: Frío 9300K'),
    LuxMenuEntry(0, '', separator: true),
    LuxMenuEntry(40, 'Salir de Lux'),
  ];

  /// Actionable entries only (separators excluded).
  static List<LuxMenuEntry> get actionable =>
      entries.where((e) => !e.separator).toList();
}

class LuxTray {
  final Future<void> Function() onToggleWindow;
  final Future<void> Function() onShowWindow;
  final Future<void> Function() onQuit;
  final Future<void> Function()? onChanged;

  DBusClient? _client;
  _LuxItem? _item;
  _LuxMenuObject? _menu;
  String _serviceName = '';
  int _revision = 1;
  bool _ready = false;

  LuxTray({
    required this.onToggleWindow,
    required this.onShowWindow,
    required this.onQuit,
    this.onChanged,
  });

  Future<void> initSafe() async {
    try {
      _client = DBusClient.session();
      _serviceName =
          'org.kde.StatusNotifierItem-$pid-lux';
      await _client!.requestName(_serviceName);
      _item = _LuxItem(onActivate: onShowWindow, onSecondary: onToggleWindow, onScroll: _onScroll);
      _menu = _LuxMenuObject(onEvent: _onMenuEvent);
      await _client!.registerObject(_item!);
      await _client!.registerObject(_menu!);
      final watcher = DBusRemoteObject(
        _client!,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      await watcher.callMethod(
        'org.kde.StatusNotifierWatcher',
        'RegisterStatusNotifierItem',
        [DBusString(_serviceName)],
      );
      _ready = true;
      debugPrint('lux: tray registered as $_serviceName');
    } catch (e) {
      debugPrint('lux: tray unavailable: $e');
    }
  }

  /// No dynamic labels: bump revision so hosts re-read the model.
  Future<void> refreshMenu({String? status}) async {
    if (!_ready) return;
    _revision++;
    try {
      _menu?.emitSignal(
        'com.canonical.dbusmenu',
        'LayoutUpdated',
        [DBusUint32(_revision), DBusInt32(0)],
      );
    } catch (e) {
      debugPrint('lux: tray refresh failed: $e');
    }
  }

  Future<void> _onMenuEvent(int id) async {
    try {
      switch (id) {
        case 1:
          await onToggleWindow();
        case 10:
          await DdcService.applyPreset('night');
        case 11:
          await DdcService.applyPreset('reading');
        case 12:
          await DdcService.applyPreset('day');
        case 20:
          await ColorService.applyProfile('gaming');
        case 21:
          await ColorService.applyProfile('code');
        case 22:
          await ColorService.applyProfile('video');
        case 23:
          await ColorService.applyProfile('read');
        case 24:
          await ColorService.clearTemperature();
        case 30:
        case 31:
        case 32:
          final tone = HwTones.byName(
            {30: 'srgb', 31: 'cool75', 32: 'cool93'}[id]!,
          );
          if (tone != null) {
            final monitors =
                await DdcService.detect(withLevels: false);
            for (final m in monitors) {
              await DdcService.setColorPreset(m.id, tone.preset14);
            }
          }
        case 40:
          await onQuit();
      }
    } on LuxException catch (e) {
      debugPrint('lux: tray action failed: $e');
    }
    await onChanged?.call();
  }

  /// Vertical scroll on the icon nudges backlight ±5 on all monitors.
  Future<void> _onScroll(int delta) async {
    try {
      final monitors = await DdcService.detect();
      for (final m in monitors) {
        final cur = m.brightness ?? 50;
        await DdcService.setBrightness(m.id, cur + delta);
      }
      await onChanged?.call();
    } on LuxException catch (e) {
      debugPrint('lux: tray scroll failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _client?.close();
    } catch (e) {
      debugPrint('lux: tray close failed: $e');
    }
    _ready = false;
  }

  int get revision => _revision;
  bool get isReady => _ready;
}

class _LuxItem extends DBusObject {
  final Future<void> Function() onActivate;
  final Future<void> Function() onSecondary;
  final Future<void> Function(int delta) onScroll;

  _LuxItem({
    required this.onActivate,
    required this.onSecondary,
    required this.onScroll,
  }) : super(DBusObjectPath('/StatusNotifierItem'));

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          'org.kde.StatusNotifierItem',
          methods: [
            DBusIntrospectMethod('ContextMenu',
                args: [DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
                       DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_)]),
            DBusIntrospectMethod('Activate',
                args: [DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
                       DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_)]),
            DBusIntrospectMethod('SecondaryActivate',
                args: [DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
                       DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_)]),
            DBusIntrospectMethod('Scroll',
                args: [DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
                       DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_)]),
          ],
          properties: [
            DBusIntrospectProperty('Category', DBusSignature('s')),
            DBusIntrospectProperty('Id', DBusSignature('s')),
            DBusIntrospectProperty('Title', DBusSignature('s')),
            DBusIntrospectProperty('Status', DBusSignature('s')),
            DBusIntrospectProperty('WindowId', DBusSignature('u')),
            DBusIntrospectProperty('IconName', DBusSignature('s')),
            DBusIntrospectProperty('OverlayIconName', DBusSignature('s')),
            DBusIntrospectProperty('AttentionIconName', DBusSignature('s')),
            DBusIntrospectProperty('Menu', DBusSignature('o')),
            DBusIntrospectProperty('ItemIsMenu', DBusSignature('b')),
          ],
        ),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(
      DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.kde.StatusNotifierItem') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'ContextMenu':
        return DBusMethodSuccessResponse();
      case 'Activate':
        unawaited(onActivate());
        return DBusMethodSuccessResponse();
      case 'SecondaryActivate':
        unawaited(onSecondary());
        return DBusMethodSuccessResponse();
      case 'Scroll':
        final dy = methodCall.values[0].asInt32();
        final orientation = methodCall.values[1].asString();
        if (orientation == 'vertical') {
          unawaited(onScroll(dy > 0 ? -5 : 5));
        }
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(
      String interface, String name) async {
    if (interface != 'org.kde.StatusNotifierItem') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final v = _properties()[name];
    if (v == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(v);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != 'org.kde.StatusNotifierItem') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_properties());
  }

  Map<String, DBusValue> _properties() => {
        'Category': DBusString('ApplicationStatus'),
        'Id': DBusString('lux'),
        'Title': DBusString('Lux — monitor brightness'),
        'Status': DBusString('Active'),
        'WindowId': DBusUint32(0),
        'IconName': DBusString('lux'),
        'OverlayIconName': DBusString(''),
        'AttentionIconName': DBusString(''),
        'Menu': DBusObjectPath('/Menu'),
        'ItemIsMenu': DBusBoolean(false),
      };
}

class _LuxMenuObject extends DBusObject {
  final Future<void> Function(int id) onEvent;

  _LuxMenuObject({required this.onEvent})
      : super(DBusObjectPath('/Menu'));

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          'com.canonical.dbusmenu',
          methods: [
            DBusIntrospectMethod('GetLayout', args: [
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.out),
              DBusIntrospectArgument(DBusSignature('(ia{sv}av)'), DBusArgumentDirection.out),
            ]),
            DBusIntrospectMethod('GetGroupProperties', args: [
              DBusIntrospectArgument(DBusSignature('ai'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('as'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('a(ia{sv})'), DBusArgumentDirection.out),
            ]),
            DBusIntrospectMethod('GetProperty', args: [
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('v'), DBusArgumentDirection.out),
            ]),
            DBusIntrospectMethod('Event', args: [
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('v'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('u'), DBusArgumentDirection.in_),
            ]),
            DBusIntrospectMethod('AboutToShow', args: [
              DBusIntrospectArgument(DBusSignature('i'), DBusArgumentDirection.in_),
              DBusIntrospectArgument(DBusSignature('b'), DBusArgumentDirection.out),
            ]),
          ],
        ),
      ];

  Map<String, DBusValue> _propsFor(LuxMenuEntry e) {
    if (e.separator) return {'type': DBusString('separator')};
    return {
      'type': DBusString('standard'),
      'label': DBusString(e.label),
      'enabled': DBusBoolean(true),
      'visible': DBusBoolean(true),
    };
  }

  DBusValue _node(LuxMenuEntry e) => DBusStruct([
        DBusInt32(e.id),
        DBusDict.stringVariant(_propsFor(e)),
        DBusArray(DBusSignature('v'), []),
      ]);

  @override
  Future<DBusMethodResponse> handleMethodCall(
      DBusMethodCall methodCall) async {
    if (methodCall.interface != 'com.canonical.dbusmenu') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'GetLayout':
        final root = DBusStruct([
          DBusInt32(0),
          DBusDict.stringVariant(
              {'children-display': DBusString('submenu')}),
          DBusArray(
            DBusSignature('v'),
            LuxMenu.entries.map((e) => DBusVariant(_node(e))).toList(),
          ),
        ]);
        return DBusMethodSuccessResponse([DBusUint32(1), root]);
      case 'GetGroupProperties':
        final ids =
            (methodCall.values[0] as DBusArray).children.cast<DBusInt32>();
        final out = ids.map((wanted) {
          final e = LuxMenu.entries.firstWhere(
            (e) => e.id == wanted.value,
            orElse: () => const LuxMenuEntry(-1, ''),
          );
          return DBusStruct([
            DBusInt32(wanted.value),
            DBusDict.stringVariant(
                e.id == -1 ? {} : _propsFor(e)),
          ]);
        }).toList();
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ia{sv})'), out),
        ]);
      case 'GetProperty':
        final id = methodCall.values[0].asInt32();
        final name = methodCall.values[1].asString();
        final e = LuxMenu.entries.where((e) => e.id == id);
        if (e.isEmpty) return DBusMethodErrorResponse.unknownProperty();
        final v = _propsFor(e.first)[name];
        if (v == null) return DBusMethodErrorResponse.unknownProperty();
        return DBusMethodSuccessResponse([DBusVariant(v)]);
      case 'Event':
        final id = methodCall.values[0].asInt32();
        final eventId = methodCall.values[1].asString();
        if (eventId == 'clicked') {
          unawaited(onEvent(id));
        }
        return DBusMethodSuccessResponse();
      case 'AboutToShow':
        return DBusMethodSuccessResponse([DBusBoolean(false)]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}
