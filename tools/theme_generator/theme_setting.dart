import 'dart:io';

import '../shared/app_locator.dart';
import '../shared/toolchain.dart';

/// Generates the splash screen and launcher icons for one app from the
/// `flutter_native_splash-*.yaml` / `icons_launcher-*.yaml` files at the
/// repository root.
///
/// ```bash
/// dart tools/theme_generator/theme_setting.dart              # the only app
/// dart tools/theme_generator/theme_setting.dart --app mobile # one of several
/// ```
void main(List<String> args) async {
  stdout.writeln('==========================================');
  stdout.writeln('       Theme and Asset Generator');
  stdout.writeln('==========================================');

  reportToolchain();
  final dartCmd = dartExecutable;

  // Configs copied into the app for the generators, removed afterwards even
  // when a generator fails — otherwise they are left behind in apps/<id>/.
  final copied = <File>[];

  try {
    // 1. Copy config files to app directory
    stdout.writeln('[!] Copying configuration files to app directory...');
    final rootDir = Directory.current;
    final appDir = Directory(selectApp(args).dir);
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
      copied.add(file.copySync('$appPath/$fileName'));
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

    stdout.writeln('==========================================');
    stdout.writeln('[V] Splash & Icon generation complete!');
    stdout.writeln('==========================================');
  } catch (e) {
    stderr.writeln('[ERROR] $e');
    exitCode = 1;
  } finally {
    stdout.writeln('[!] Cleaning up temporary configuration files...');
    for (final file in copied) {
      if (file.existsSync()) file.deleteSync();
    }
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

  final code = await result.exitCode;
  if (code != 0) {
    // Thrown, not `exit`: the caller's `finally` must still clean up.
    throw Exception(
      'Command "$command ${args.join(' ')}" failed with exit code $code',
    );
  }
}
