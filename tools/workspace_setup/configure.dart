import 'dart:io';

import '../shared/toolchain.dart';

void main() async {
  stdout.writeln('==========================================');
  stdout.writeln('      Project Configuration Setup');
  stdout.writeln('==========================================');

  // The same two-signal FVM detection every tool uses.
  reportToolchain();
  final flutterCmd = flutterExecutable;
  final dartCmd = dartExecutable;

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

  // 5. Code generation for the whole workspace — injectable, freezed,
  // json_serializable, retrofit, go_router_builder, drift. No generated file
  // is committed, so nothing past `pub get` compiles until this has run.
  stdout.writeln('[!] Running build_runner for the workspace...');
  await _runCommand(dartCmd, [
    ...dartArgs,
    'run',
    'build_runner',
    'build',
    '-d',
    '--workspace',
  ]);

  // 6. Generate barrel files — one package at a time.
  //
  // This used to pass `packages` as a single argument. The generator emits a
  // barrel for whatever directory it is handed, so that produced
  // `packages/packages.dart`, `platform/core.dart` and
  // `platform/database/database.dart` — files sitting outside every
  // `lib/`, which nothing can import and which nobody noticed. They were
  // deleted; this is what stops them coming back.
  stdout.writeln('[!] Generating barrel files per package...');
  for (final pubspec in _findFiles(Directory('.'), 'pubspec.yaml')) {
    final pkgDir = pubspec.parent.path;
    final lib = Directory('$pkgDir/lib');
    if (!lib.existsSync()) continue;
    // An app is a composition root, not a library: nothing imports it, and
    // its `injection.dart` is composer's output — a barrel pass would add an
    // app barrel and reformat a file `composer verify` compares byte-for-byte.
    if (File('$pkgDir/app_manifest.yaml').existsSync()) continue;
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
