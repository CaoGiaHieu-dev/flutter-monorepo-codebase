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
    final appDir = Directory('app');

    if (!appDir.existsSync()) {
      stderr.writeln('[ERROR] "app" directory not found.');
      exit(1);
    }

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
      file.copySync('app/$fileName');
    }

    // 2. Running Flutter Native Splash Generator
    stdout.writeln('[!] Running Flutter Native Splash Generator...');
    await _runCommand(dartCmd, [
      ...dartArgs,
      'run',
      'flutter_native_splash:create',
      '--flavors',
      'dev,staging,prod',
    ], workingDirectory: 'app');

    // 3. Running Icons Launcher Generator
    stdout.writeln('[!] Running Icons Launcher Generator...');
    await _runCommand(dartCmd, [
      ...dartArgs,
      'run',
      'icons_launcher:create',
      '--flavors',
      'dev,staging,prod',
    ], workingDirectory: 'app');

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
