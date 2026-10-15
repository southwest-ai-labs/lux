# Monitor controls available over DDC/CI

Source: `ddcutil --display 1 capabilities` on the AOC 24G42HE (DP-1), read on
2026-10-15. The panel reports its model as `Q27G4D` in the capability string;
`ddcutil detect` reports `24G42HE` for the same display, and the preset and
input values match the ones verified in the README.

Only what the panel advertises is listed. A code is never sent unless the
panel lists it, and every write must restore the previous value.

## 1. Already in Lux

| Feature | VCP | Values | Status |
|---|---|---|---|
| Brightness | 0x10 | 0-100 | shipped |
| Contrast | 0x12 | 0-100 | shipped |
| Colour preset | 0x14 | 05 6500K, 06 7500K, 08 9300K, 0B User 1 | shipped |
| RGB gains | 0x16 / 0x18 / 0x1A | 0-100, needs User 1 | shipped |
| Input source | 0x60 | 0F DP-1, 11 HDMI-1 | shipped (allowlist) |
| Speaker volume | 0x62 | 0-100 | shipped |
| Power mode | 0xD6 | 01 on, 04 off | shipped (2/3 not exposed) |

## 2. Safe to add: standard codes, round-trip verifiable

| Feature | VCP | Values advertised | Notes |
|---|---|---|---|
| Display scaling | 0x86 | 01 no scaling, 02 max image without distortion, 05 max vertical with distortion | Only the three listed values. 0B-11 are "Unrecognized value", never send them. |
| Display mode | 0xDC | 00 Standard | Only one value; read-only unless more appear. |
| Active control | 0x52 | read | Read-only status. |
| Colour temperature request | 0x0C | read | Read-only. |

## 3. Read-only information (useful in the UI and in `luxctl doctor`)

| Feature | VCP | Use |
|---|---|---|
| Horizontal / vertical frequency | 0xAC / 0xAE | Show current refresh path. |
| Flat-panel sub-pixel layout | 0xB2 | Info card. |
| Display technology type | 0xB6 | Info card. |
| Display controller type | 0xC8 | Info card, helps bug reports. |
| VCP version | 0xDF | Info (MCCS 2.2). |

## 4. Needs mapping before exposing (interpretation unknown)

These codes are advertised, but the panel gives no value names. Each needs a
read-only probe and an on-screen check with the OSD before any write:

- 0x8D audio mute / screen blank (already listed as "write prohibited" in ROADMAP).
- 0x13 backlight control, values 00 01 (may be a real hardware backlight switch).
- 0x11 flesh tone, 0x20 horizontal phase, 0x45, 0x4A bottom corner flare, 0x4B.
- 0x51, 0x55, 0x56 horizontal moire, 0x57, 0x58 vertical moire, 0x59 six-axis saturation red.
- 0xA0 six-axis hue magenta.
- 0xCA OSD / button control (could lock the OSD; a mistake needs the OSD to undo).
- 0xCC OSD language (a wrong language can make the OSD unreadable).
- Manufacturer-specific codes 0xE1, 0xE2, 0xED, 0xF8 (no names).

## 5. Excluded

- 0x04 restore factory defaults, 0x05 restore factory brightness and contrast,
  0x08 restore colour defaults: destructive, no benefit.
- 0xD6 values 02, 03 (standby, suspend): wake behaviour is not verified.
- 0x60 values outside the allowlist: a wrong input means no signal.
- 0x14 values outside the allowlist: the panel rejects them, and they can shift colour.

## Roadmap

1. v0.7.0: read-only info card (section 3) and `luxctl doctor` shows it.
2. v0.7.x: display scaling (0x86) with the three advertised values and a round trip check.
3. Later: map section 4 codes with OSD photos, one code per change, each with a restore step.
