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

  /// Directories searched, in order, when a tool is missing from PATH.
  /// A launcher can start Lux with a PATH that lacks the NixOS profiles, which
  /// made `ddcutil` look uninstalled even though it is present.
  static List<String> Function() fallbackDirs = _defaultFallbackDirs;

  static List<String> _defaultFallbackDirs() {
    final home = Platform.environment['HOME'] ?? '';
    final user = Platform.environment['USER'] ?? '';
    return [
      '/run/current-system/sw/bin',
      if (home.isNotEmpty) '$home/.nix-profile/bin',
      if (user.isNotEmpty) '/etc/profiles/per-user/$user/bin',
      '/usr/local/bin',
      '/usr/bin',
    ];
  }

  /// Runs [name] from PATH, or from the first fallback directory that holds
  /// it. Rethrows the original [ProcessException] when none does.
  static Future<ProcessResult> runTool(String name, List<String> args) async {
    try {
      return await run(name, args);
    } on ProcessException {
      for (final dir in fallbackDirs()) {
        final path = '$dir/$name';
        if (File(path).existsSync()) {
          return run(path, args);
        }
      }
      rethrow;
    }
  }
}
