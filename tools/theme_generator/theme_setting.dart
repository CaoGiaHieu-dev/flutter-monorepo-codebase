import 'dart:io';

void main() async {
  stdout.writeln('==========================================');
  stdout.writeln('       Theme and Asset Generator');
  stdout.writeln('==========================================');

  // Detect FVM: Only use it if .fvm/fvm_config.json exists
  final hasFvmConfig = File('.fvm/fvm_config.json').existsSync();
  final dartCmd = hasFvmConfig ? 'fvm' : 'dart';
  final dartArgs = hasFvmConfig ? ['dart'] : <String>[];

  if (hasFvmConfig) {
    stdout.writeln('[INFO] Detected FVM config. Using FVM CLI.');
  } else {
    stdout.writeln(
      '[INFO] FVM config not detected. Using global Flutter/Dart SDK.',
    );
  }

  try {
    // 1. Copy config files to app directory
    stdout.writeln('[!] Copying configuration files to app directory...');
    final rootDir = Directory.current;
    final appDir = _findAppDirectory();
    final appPath = appDir.path;

    final configFiles = rootDir
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              file.path.contains('flutter_native_splash-') ||
              file.path.contains('icons_launcher-'),
        )
        .toList();

    for (final file in configFiles) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      file.copySync('$appPath/$fileName');
    }

    // 2. Running Flutter Native Splash Generator
    stdout.writeln('[!] Running Flutter Native Splash Generator...');
    await _runCommand(dartCmd, [
      ...dartArgs,
      'run',
      'flutter_native_splash:create',
      '--flavors',
      'dev,staging,prod',
    ], workingDirectory: appPath);

    // 3. Running Icons Launcher Generator
    stdout.writeln('[!] Running Icons Launcher Generator...');
    await _runCommand(dartCmd, [
      ...dartArgs,
      'run',
      'icons_launcher:create',
      '--flavors',
      'dev,staging,prod',
    ], workingDirectory: appPath);

    // 4. Cleanup: Remove copied config files from app
    stdout.writeln('[!] Cleaning up temporary configuration files...');
    final appConfigs = appDir
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              file.path.contains('flutter_native_splash-') ||
              file.path.contains('icons_launcher-'),
        )
        .toList();

    for (final file in appConfigs) {
      file.deleteSync();
    }

    stdout.writeln('==========================================');
    stdout.writeln('[V] Splash & Icon generation complete!');
    stdout.writeln('==========================================');
  } catch (e) {
    stderr.writeln('[ERROR] An unexpected error occurred: $e');
    exit(1);
  }
}

Future<void> _runCommand(
  String command,
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await Process.start(
    command,
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln(
      '[ERROR] Command "$command ${args.join(' ')}" failed with exit code $exitCode',
    );
    exit(exitCode);
  }
}

/// Locates the Flutter app this tool should generate assets for.
///
/// An app is a directory holding an `app_manifest.yaml` — the same marker
/// `composer` uses — so this keeps working after a relayout. It used to be the
/// literal string `'app'`, which stopped existing the day the app moved to
/// `apps/mobile/`.
///
/// With more than one app in the workspace, generating icons for an arbitrary
/// one would be worse than refusing: say which, and let the caller decide.
Directory _findAppDirectory() {
  final manifests = Directory.current
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) {
        final path = f.path.replaceAll('\\', '/');
        return path.endsWith('/app_manifest.yaml') &&
            !path.contains('/build/') &&
            !path.contains('/.dart_tool/');
      })
      .toList();

  if (manifests.isEmpty) {
    stderr.writeln(
      '[ERROR] No app found: nothing in this workspace contains an '
      'app_manifest.yaml.',
    );
    exit(1);
  }
  if (manifests.length > 1) {
    stderr.writeln(
      '[ERROR] ${manifests.length} apps found; this tool generates for one:',
    );
    for (final m in manifests) {
      stderr.writeln('  - ${File(m.path).parent.path}');
    }
    stderr.writeln('Run it from inside the app you mean.');
    exit(1);
  }
  return File(manifests.single.path).parent;
}
