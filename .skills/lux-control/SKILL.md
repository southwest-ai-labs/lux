---
name: lux-control
description: "Use when adjusting monitor brightness/contrast on this machine (Lux app). Drives the local Lux HTTP API or the luxctl CLI via DDC/CI."
version: 1.0.0
author: Hermes Agent
tags: [lux, ddc-ci, monitor, brightness, linux, tray]
---

# Lux Control — Agent Skill

Drive the user's monitors (brightness/contrast) via the Lux app. Hardware
control through DDC/CI (VESA MCCS) — this changes the panel backlight, unlike
night-light/gamma filters which only shift colors.

## Discovery order

1. Prefer the HTTP API when the Lux app is running (fast, structured).
2. Fallback to `luxctl` CLI — works even with the GUI closed.

## HTTP API (loopback only)

Base: `http://127.0.0.1:19847/v1`
Auth: `Authorization: Bearer <token>` where token = content of
`~/.config/lux/token` (file is 0600, loopback-only, never exfiltrate it).

- List: `GET /v1/monitors` → `[{id, drm, make, model, serial, label, brightness, contrast}]`
- Read one: `GET /v1/monitors/1`
- Set: `PUT /v1/monitors/1 {"brightness": 20}` (0-100; `contrast` optional too)
- Presets: `POST /v1/presets/night|reading|day` (15 / 35 / 80 on ALL monitors)
- Self-doc: `GET /v1/skill`
- Health (no auth): `GET /v1/health`

Example:

```bash
T=$(cat ~/.config/lux/token)
curl -s http://127.0.0.1:19847/v1/monitors -H "Authorization: Bearer $T"
curl -s -X PUT http://127.0.0.1:19847/v1/monitors/1 \
  -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"brightness": 20}'
```

## CLI fallback

```bash
~/proyectosSWAL/apps/lux/scripts/luxctl doctor          # diagnose i2c/ddcutil
~/proyectosSWAL/apps/lux/scripts/luxctl detect
~/proyectosSWAL/apps/lux/scripts/luxctl set 1 brightness 20
~/proyectosSWAL/apps/lux/scripts/luxctl preset night
```

## VCP reference (generic, all brands)

| Code | Name | Range |
|------|------|-------|
| 0x10 | Brightness | 0-100 |
| 0x12 | Contrast | 0-100 |

## Profiles (display + color)

- `GET /v1/profiles`, `POST /v1/profiles/gaming|code|video|read`,
  `DELETE /v1/temperature` (restore previous night-light)
- CLI: `luxctl profile leer`, `luxctl temp 4500`, `luxctl temp off`
- Temperature works NOW (wlsunset takeover, previous cmdline restored on
  clear); brightness needs i2c. Report both parts from the response; never
  claim brightness applied when `brightness.error` is set.
- Taking over gamma kills the user's own wlsunset (first saved cmdline wins,
  restored on clear/quit). Mention it when a profile changes their night mode.

## Rules

- Brightness/contrast writes are SAFE (no confirmation needed); stay within
  5-90 unless the user explicitly asks for extremes.
- NEVER touch VCP 0x60 (input source) or factory-reset codes — that can lose
  the user's signal or calibration.
- If reads fail with i2c errors, report it (needs `hardware.i2c.enable = true`
  + `i2c` group + relogin on NixOS) instead of retrying blindly.
- `null` brightness in a response means that panel doesn't report the level;
  writes usually still work.
- The token is a local secret: use it from the file, never print it, never
  send it anywhere off-machine.
