import 'dart:io';

void main() async {
  stdout.writeln('==========================================');
  stdout.writeln('      Project Configuration Setup');
  stdout.writeln('==========================================');

  // Detect FVM: Only use it if .fvm/fvm_config.json exists
  final hasFvmConfig = File('.fvm/fvm_config.json').existsSync();
  final flutterCmd = hasFvmConfig ? 'fvm' : 'flutter';
  final dartCmd = hasFvmConfig ? 'fvm' : 'dart';

  final flutterArgs = hasFvmConfig ? ['flutter'] : <String>[];
  final dartArgs = hasFvmConfig ? ['dart'] : <String>[];

  if (hasFvmConfig) {
    stdout.writeln('[INFO] Detected FVM config. Using FVM CLI.');
  } else {
    stdout.writeln(
      '[INFO] FVM config not detected. Using global Flutter/Dart SDK.',
    );
  }

  // 1. Activating global CLIs
  stdout.writeln('[!] Activating global CLIs...');
  await _runCommand(flutterCmd, [
    ...dartArgs,
    'pub',
    'global',
    'activate',
    'flutterfire_cli',
  ]);

  // 2. Running Flutter clean
  stdout.writeln('[!] Running Flutter clean...');
  await _runCommand(flutterCmd, [...flutterArgs, 'clean']);

  // 3. Running Flutter pub get for workspace
  stdout.writeln('[!] Running Flutter pub get for workspace...');
  await _runCommand(flutterCmd, [...flutterArgs, 'pub', 'get']);

  // 4. Generating localization
  stdout.writeln('[!] Generating localization for all packages...');
  final packagesDir = Directory('packages');
  if (packagesDir.existsSync()) {
    final l10nFiles = packagesDir
        .listSync(recursive: true)
        .where((e) => e is File && e.path.endsWith('l10n.yaml'));

    if (l10nFiles.isEmpty) {
      stdout.writeln('    - No l10n.yaml found in packages.');
    } else {
      for (final file in l10nFiles) {
        final pkgDir = file.parent.path;
        stdout.writeln('    - Generating for: $pkgDir');
        await _runCommand(flutterCmd, [
          ...flutterArgs,
          'gen-l10n',
        ], workingDirectory: pkgDir);
      }
    }
  }

  // 5. Building code generation
  stdout.writeln('[!] Building code generation...');
  final buildRunnerArgs = hasFvmConfig
      ? [
          'dart',
          'run',
          'build_runner',
          'build',
          '--delete-conflicting-outputs',
          '--workspace',
        ]
      : [
          'run',
          'build_runner',
          'build',
          '--delete-conflicting-outputs',
          '--workspace',
        ];
  await _runCommand(dartCmd, buildRunnerArgs);

  // 6. Generate barrel file
  await _runCommand(dartCmd, [
    ...dartArgs,
    'tools/barrel_generator/generate.dart',
    'packages',
  ]);

  stdout.writeln('==========================================');
  stdout.writeln('[V] Configuration completed successfully!');
  stdout.writeln('==========================================');
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
