# Agents Guide for southwest-ai-labs/lux

Welcome to the Lux repository. This is an agent guide to assist in automating CI, linting, code modifications, and repository maintenance.

## Project Facts
- **Repository:** `southwest-ai-labs/lux`
- **Version:** Lux 0.5.0
- **Type:** DDC/CI monitor brightness control for Linux (tray + profiles + HW tones).
- **Environment:** Linux-first (headless tray app). Do not execute builds for Windows, macOS, or mobile.
- **Language:** Dart/Flutter

## Commands
For local verification and CI tests, always run the following commands in the root of the repository:

1. **Linting:**
   ```bash
   flutter analyze --no-fatal-infos
   ```
   Ensure 0 errors before submitting code.

2. **Testing:**
   ```bash
   flutter test
   ```
   All tests must pass. We do not fake test results. Document any toolchain absence appropriately.

## Dependencies and Core Rules
- **Dependencies:** The app relies on `dbus` and `window_manager`. Keep these dependencies intact.
- **Cores Note:** Do not introduce any `@swal/*` dependencies or consumption in this repository.
- **Hardware Access:** The CI should only perform unit testing and analysis. It must **not** include hardware access operations like `ddcutil`, `i2c`, or `/dev/i2c`.

## PR and Contribution Rules
- **Language:** All pull requests, code, comments, and documentation must be in English.
- **Evidence-First:** Ensure all changes are measurable and verified by command execution before submitting.
- **Merging Strategy:** Bel merges all PRs.
- **Clean Slate:** Ensure zero local dirt unless explicitly allowed (e.g., `.husky/`).

## License
Lux is governed by the Apache-2.0 License. This must not be altered, and any relicensing is strictly prohibited. Keep `LICENSE` intact.


## Security
Do not expose or commit secrets such as tokens, passwords, or keys. Ensure CI definitions are free from hardware access tools.
