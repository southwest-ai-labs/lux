import 'dart:io';

/// Runs an external command and returns its result.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// The single place where Lux starts external commands (`ddcutil`,
/// `hyprshade`, `which`). Production uses [Process.run]; the headless e2e
/// suite swaps it for a fake so no test ever touches I2C or the compositor.
abstract final class Shell {
  static ProcessRunner run = Process.run;
}
