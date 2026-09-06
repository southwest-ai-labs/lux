# Lux — DDC/CI monitor brightness for Linux

Flutter Linux app that lives in the system tray and controls REAL panel
backlight via DDC/CI (VESA MCCS over I2C), plus a loopback HTTP API + CLI so
LLM agents can drive it through the `lux-control` skill.

## Why this exists

Night-light / gamma filters (Hyprsunset, Gammastep, GNOME Night Light) only
shift colors — they never lower the backlight. If the screen still blinds you
at night, you need hardware brightness: VCP `0x10` over DDC/CI. That works on
practically every external monitor (DP/HDMI/DVI/VGA) from every brand,
including the AOC 24G42HE this was built for.

## Approach (generic, not brand-specific)

- Transport: DDC/CI over the display cable's I2C bus (`ddcutil` CLI).
- Controls: VCP `0x10` brightness + `0x12` contrast (VESA MCCS standard).
- Discovery: `ddcutil detect` → per-display `--display N getvcp/setvcp`.
- Graceful degradation: panels that don't report a level show `null` but
  still accept writes; panels without DDC/CI report a clear error telling
  the user to enable DDC/CI in the monitor OSD.
- Presets: Night 15% / Reading 35% / Day 80% (tray menu, window, API, CLI).

## NixOS setup (required once)

```nix
hardware.i2c.enable = true;                       # creates /dev/i2c-*, i2c group
users.users.belal.extraGroups = [ "i2c" ];        # permission to talk to panels
environment.systemPackages = with pkgs; [
  ddcutil
  libayatana-appindicator   # tray icon runtime (verify name: nix search nixpkgs libayatana-appindicator)
];
```

Then `sudo nixos-rebuild switch --flake /etc/nixos#swal` and **relogin**.
Verify with: `scripts/luxctl doctor`.

Build deps for the Flutter app (NixOS workaround, see `flutter-development`
skill): flutter, cmake, ninja, pkg-config, gtk3 dev, ayatana-appindicator dev.

```bash
nix-shell -p flutter cmake ninja pkg-config gtk3.dev libayatana-appindicator \
  --run "DESTDIR=/tmp/lux-build flutter build linux --release"
# binary: /tmp/lux-build/var/empty/local/lux
```

Autostart (Hyprland): `exec-once = /path/to/lux`
Desktop entry: see `assets/lux.desktop`.

## Layout

```
lib/main.dart            entry: window + tray + API wiring
lib/src/ddc_service.dart ONLY place that speaks ddcutil (VCP codes)
lib/src/api_server.dart  loopback HTTP API :19847 (token in ~/.config/lux/token)
lib/src/tray_controller.dart  StatusNotifier tray (Hyprland/Waybar compatible)
lib/src/app.dart         settings window (sliders, presets, API card)
lib/src/models.dart      MonitorInfo, LuxException, LuxPresets
scripts/luxctl           headless CLI (agents use it when GUI is closed)
.skills/lux-control/     agent skill (HTTP + CLI contract)
test/ddc_parse_test.dart parser unit tests (no hardware needed)
```

## Agent access

- App running: `GET/PUT http://127.0.0.1:19847/v1/...` (`GET /v1/skill` self-docs).
- App closed: `scripts/luxctl ...` (same VCP codes, same presets).
- Full contract: `.skills/lux-control/SKILL.md`.

## Status

v0.1.0 — INSTALLED 2026-09-06 (`~/.local/bin/lux`, `~/.local/bin/luxctl`,
`~/.local/share/applications/lux.desktop`). Smoke-tested: window maps in
Hyprland, API enforces token, errors guide to the NixOS i2c fix.
Hardware dimming pending: `hardware.i2c.enable = true` + `i2c` group.
Next: per-monitor saved profiles, scheduler (auto-night), gamma fallback
(hyprsunset) for panels without DDC/CI.
