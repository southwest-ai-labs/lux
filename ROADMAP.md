# Lux ROADMAP — control total del monitor (AOC 24G42HE + genéricos DDC/CI)

> Principio: solo se expone lo verificado en vivo contra hardware.
> Códigos nuevos entran por `capabilities` + round-trip, nunca inventados.

## v0.5.0 — Controles extra DDC + GPU (ESTE TURNO, en curso)

- [x] Entrada DP/HDMI (0x60 allowlist 0F/11) — `luxctl input`
- [x] Volumen (0x62 round-trip 95) — `luxctl volume`
- [x] Power on/off DDC (0xD6 1/4, wake verificado) — `luxctl power`
- [x] Refresh GPU 60/120/144/200 (hyprctl) — `luxctl refresh`
- [x] DPMS sleep (hyprctl) — `luxctl dpms`
- [x] Modo auto circadiano sin daemon — `luxctl auto`
- [ ] UI: tarjetas Entrada/Volumen/Power en la ventana (solo falta UI)
- [ ] Scheduler con daemon: Timer en app + persistencia (auto cada hora)
- [ ] Commit + push v0.5.0

## v0.6.0 — Investigación abierta (lectura segura primero)

- 0x8D mute/blank: ESCRITURA PROHIBIDA hasta entender bits (x02 actual
  con pantalla encendida — mapear bits con OSD antes de tocar).
- 0x86 scaling (actual x02 nativo): exponer solo lectura + presets
  documentados del OSD.
- 0xCA OSD lock / 0xCC idioma: útil para kioscos, riesgo bajo, sin
  demanda aún.
- Overdrive / response time / FPS counter: AOC no lo expone por DDC
  (sin códigos E2/E3 de fabricante en capabilities) → solo OSD.
  Alternativa real: reglas Hyprland por juego (refresh+gamemode).
- Brillo por zona / HDR: fuera de MCCS en este panel.

## v1.0.0 — Producto cerrado

- Módulo NixOS opcional (`services.lux.enable`: i2c + udev + autostart).
- Perfiles por monitor (multi-display real, hoy: primer monitor).
- Scheduler daemon + atajos globales Hyprland (binds para brillo/perfil).
- Empaquetado: tarball + .desktop (sin store: regla de datos móviles).
- Suite e2e contra hardware: round-trips con restore garantizado
  (LECCIÓN 2026-09-06: jamás meter valores permitidos en listas de
  rechazo de tests — tocan hardware real).

## Descartado (con motivo)

- 0x04/0x05/0x08 resets de fábrica: destructivos, cero beneficio.
- 0x60 fuera de allowlist: pérdida de señal = pantalla negra.
- 0xD6 standby/suspend (2/3): wake sin verificar en este panel.
- LowBlue propietario AOC: no existe código DDC (verificado en
  capabilities + investigación L2) → shaders hyprshade.
- Calidez <6500K por hardware: el panel no la tiene → shaders.
- Builds Windows/macOS aquí: imposible sin MSVC/Xcode (ver README).
