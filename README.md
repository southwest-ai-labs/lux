# Lux — DDC/CI monitor brightness for Linux

> Copyright 2026 Southwest AI Labs — Apache-2.0 (see `LICENSE`).

Flutter Linux app in the system tray. Controls REAL panel backlight via
DDC/CI (VESA MCCS over I2C) — unlike night-light filters, which only shift
colors and never lower the backlight.

## Why this exists

Night-light / gamma filters only shift colors. If the screen still blinds
you at night, you need hardware brightness: VCP `0x10` over DDC/CI. Works
on practically every external monitor (DP/HDMI) from every brand.

## Approach (generic, verified on AOC 24G42HE)

- Transport: DDC/CI over the display cable (`ddcutil` CLI).
- Brightness `0x10` + contrast `0x12` (VESA MCCS standard).
- Cool tones in hardware: presets `0x14` = 6500/7500/9300K + User1,
  fine-tuned with RGB gains `0x16/0x18/0x1A` (gains need User1 first).
  ONLY these preset values are ever sent (capabilities allowlist).
- Warm tones (<6500K, impossible in this panel's hardware) via hyprshade
  screen shaders (`~/.config/hypr/shaders/lux-*.glsl`).
- This machine's wlr gamma path is broken ("gamma control of output DP-2
  failed"), so wlsunset/gammastep cannot work here — shaders bypass it.
- Profiles: Jugar (vibrance) / Programar 5500K / Videos 4500K / Leer 4000K.

## NixOS setup (required once, permanent)

```nix
hardware.i2c.enable = true;                       # creates /dev/i2c-*, i2c group
users.users.belal.extraGroups = [ "i2c" ];        # permission to talk to panels
environment.systemPackages = with pkgs; [ ddcutil ];
```

Then `sudo nixos-rebuild switch --flake /etc/nixos#swal` and **relogin**.
Verify with: `luxctl doctor`.

## Install / build (ephemeral shell, no system change)

```bash
nix-shell -p flutter cmake ninja pkg-config gtk3.dev glib.dev pango.dev \
  atk.dev gdk-pixbuf.dev cairo.dev libayatana-appindicator \
  --run "cd ~/proyectosSWAL/apps/lux && DESTDIR=/tmp/lux-build flutter build linux --release"
cp -r /tmp/lux-build/.../bundle/. ~/.local/share/lux/
```

Autostart (Hyprland): `exec-once = lux`

## Layout

```
lib/main.dart            entry: window + tray wiring
lib/src/ddc_service.dart ONLY place that speaks ddcutil (VCP codes)
lib/src/color_service.dart hyprshade profiles (shaders)
lib/src/tray_controller.dart StatusNotifier tray (Hyprland/Waybar)
lib/src/app.dart         glass settings window (sliders, profiles, tones)
lib/src/glass_card.dart  frosted-glass surface widget
lib/src/models.dart      MonitorInfo, LuxException, profiles, HW tones
scripts/luxctl           personal CLI (doctor, detect, set, profiles, tones)
test/                    parser + table unit tests (no hardware needed)
```

## Status

See `features.json`. v0.4.0: agent API removed (simpler app, personal use).
