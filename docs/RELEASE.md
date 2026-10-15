# Lux Release Gate

Release gate for Lux. A reviewer uses it before every release or tag, including small ones.

## 1. Scope and version scheme

- Versions follow [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html).
- While the major version is `0`: a `feat` commit bumps the minor (0.6.0 -> 0.7.0), a `fix` commit bumps the patch (0.6.0 -> 0.6.1).

## 2. Single source of version

The version must be identical in three places:

- `pubspec.yaml`: `version:` line, form `version: X.Y.Z`
- `features.json`: `"version"` key, form `"version": "X.Y.Z"`
- `AGENTS.md`: `- **Version:** Lux X.Y.Z`

Check from the repository root:

```sh
grep -n '^version:' pubspec.yaml
grep -o '"version": *"[^"]*"' features.json
grep -n 'Version:\*\* Lux' AGENTS.md
```

All three must show the same `X.Y.Z`, matching the version being tagged (without the `v`). Any mismatch blocks the release.

## 3. Gates

Run every gate on the exact commit being tagged (confirm with `git rev-parse HEAD`). Paste the real output into the release notes. Never write results from memory or reuse output from another commit.

### 3.1 Clean tree

The tagged commit must come from a clean tree. The SWAL tooling appends a routing block to `AGENTS.md` and leaves `.atl/` untracked on the working copy; neither belongs to a release. Verify the commit in a clean worktree:

```sh
git worktree add --detach "$(mktemp -d)/lux-release" "$(git rev-parse HEAD)"
git -C <that path> status --short   # must print nothing
```

Run the remaining gates from that worktree. Remove it afterwards with `git worktree remove`.

### 3.2 Static analysis

Run `flutter analyze --no-fatal-infos`. It must report `No issues found`.

### 3.3 Tests

Run `flutter test`. It must report `All tests passed`. This includes the headless e2e suite in `test/e2e`.

### 3.4 Linux debug build

Run `flutter build linux --debug`. It must succeed and produce `build/linux/x64/debug/bundle/lux`.

### 3.5 Screenshots

Run `flutter test test/e2e`. A pass means `docs/screenshots` still matches the UI. If the UI changed on purpose, run `flutter test --update-goldens test/e2e`, review every regenerated PNG by eye, and commit the PNGs together with the UI change. Never regenerate goldens just to make a failing test pass.

### 3.6 Hardware guard

```sh
grep -rnE 'Process\.(run|start)' test | grep -v 'test/support/'
grep -rniE 'ddcutil|i2c' .github
```

No test may start a process itself, and CI must not touch ddcutil or i2c (repository rule in AGENTS.md). Tests reach external commands only through the `Shell.run` seam, which `test/support/fake_shell.dart` replaces. Both commands must print nothing. Test fixtures that contain ddcutil output text (for example `test/ddc_parse_test.dart`) are allowed: they are strings, not calls. This covers tests and CI only; the app's runtime use in `lib/` is not covered here.

### 3.7 features.json evidence

- Every feature claimed in the release must have `"passes": true`.
- `"passes": true` is allowed only when the feature's `evidence` line names the command that proved it (for example `flutter test test/e2e`).
- Evidence such as "verified" or a bare date does not count. If no command can be named, set `"passes"` back to `false`.

Review with `python3 -m json.tool features.json`.

## 4. Known local toolchain note

On the NixOS build machine the default `clang++` on `PATH` cannot link. The workaround used so far is a temporary directory first on `PATH` with `clang++` and `clang` symlinked to `g++` and `gcc`:

```sh
shim="$(mktemp -d)"
ln -s "$(command -v g++)" "$shim/clang++"
ln -s "$(command -v gcc)" "$shim/clang"
PATH="$shim:$PATH" flutter build linux --debug
```

This is an environment workaround only. Never commit it or add it to scripts or CI. Note in the release notes when it was used.

## 5. Tagging rules

1. Create annotated tags only: `git tag -a vX.Y.Z -m "Lux X.Y.Z"`.
2. Create the tag only after every gate in section 3 passes on that commit.
3. Create the tag only after the maintainer (Belal) has explicitly confirmed it. Green CI is not a confirmation.
4. Never re-tag a published version (no moving, recreating or deleting). A new fix means a new patch version.
5. Never tag a dirty tree. Repeat section 3.1 on the commit first.

## 6. Commit attribution

- No co-author lines, AI attribution trailers, badges or "Generated with" footers in commit messages or PR descriptions.
- Commit only under the configured git identity. Do not set or override the author.

## 7. Verdict

Copy this template into the release notes. A gate is PASS only when the quoted result matches the expected result.

Release: Lux X.Y.Z | Commit: `<git rev-parse HEAD>` | Tag confirmed by Belal: `<quote or "not yet">`

| # | Gate | Command | Quoted result | Result |
|---|---|---|---|---|
| 1 | Version match | `grep` on the three files (section 2) | `<paste>` | PASS / FAIL |
| 2 | Clean tree (clean worktree of HEAD) | `git -C <worktree> status --short` | `<paste>` | PASS / FAIL |
| 3 | Analyze | `flutter analyze --no-fatal-infos` | `<paste>` | PASS / FAIL |
| 4 | Tests | `flutter test` | `<paste>` | PASS / FAIL |
| 5 | Linux debug build | `flutter build linux --debug` | `<paste>` | PASS / FAIL |
| 6 | Screenshots | `flutter test test/e2e` | `<paste>` | PASS / FAIL |
| 7 | Hardware guard | `grep -rnE 'Process\.(run\|start)' test \| grep -v test/support/` and `grep -rniE 'ddcutil\|i2c' .github` | `<paste>` | PASS / FAIL |
| 8 | features.json evidence | manual review (3.7) | `<paste>` | PASS / FAIL |
| 9 | Attribution | `git log -1 --format=%B` | `<paste>` | PASS / FAIL |

Overall: PASS only when all nine rows pass. Then tag, and only with the confirmation from section 5.
