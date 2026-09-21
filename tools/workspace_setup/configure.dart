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
  // Scanned from the repository root, not from a hardcoded `packages/`: a
  // package that lives anywhere else still needs its ARBs generated, and
  // missing one fails later with an unresolved `AppLocalizations`.
  final l10nFiles = _findFiles(Directory('.'), 'l10n.yaml');

  if (l10nFiles.isEmpty) {
    stdout.writeln('    - No l10n.yaml found.');
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

  // 6. Generate barrel files — one package at a time.
  //
  // This used to pass `packages` as a single argument. The generator emits a
  // barrel for whatever directory it is handed, so that produced
  // `packages/packages.dart`, `packages/core/core.dart` and
  // `packages/core/database/database.dart` — files sitting outside every
  // `lib/`, which nothing can import and which nobody noticed. They were
  // deleted; this is what stops them coming back.
  stdout.writeln('[!] Generating barrel files per package...');
  for (final pubspec in _findFiles(Directory('.'), 'pubspec.yaml')) {
    final pkgDir = pubspec.parent.path;
    final lib = Directory('$pkgDir/lib');
    if (!lib.existsSync()) continue;
    await _runCommand(dartCmd, [
      ...dartArgs,
      'tools/barrel_generator/generate.dart',
      lib.path,
    ]);
  }

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

/// Every file named [fileName] under [dir], skipping build output and
/// platform folders.
List<File> _findFiles(Directory dir, String fileName) {
  final out = <File>[];
  const skip = {
    '.git',
    '.dart_tool',
    'build',
    'ios',
    'android',
    'macos',
    'windows',
    'linux',
    'web',
    'node_modules',
  };
  void walk(Directory d) {
    for (final e in d.listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        if (skip.contains(name) || name.startsWith('.')) continue;
        walk(e);
      } else if (e is File && name == fileName) {
        out.add(e);
      }
    }
  }

  walk(dir);
  return out;
}
