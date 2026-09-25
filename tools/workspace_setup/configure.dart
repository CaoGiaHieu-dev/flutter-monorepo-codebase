import 'dart:io';

import '../shared/toolchain.dart';
import 'firebase_stubs.dart';

const String _usage = '''
Usage: dart tools/workspace_setup/configure.dart [--stub-firebase] [--help]

Full workspace setup — the setup step on a fresh clone. Run from anywhere in
the repository; it works on the repository root. In order:

  1. dart pub global activate flutterfire_cli
  2. flutter clean
  3. flutter pub get
  4. flutter gen-l10n in every package with an l10n.yaml
  5. dart run build_runner build --workspace
  6. tools/barrel_generator/generate.dart for every package with a lib/
     (apps are skipped)

Step 2 deletes build output and .dart_tool/, and steps 5-6 rewrite every
generated file and barrel. Stops at the first failing command with its exit
code. FVM is used only when detected (tools/shared/toolchain.dart).

Options:
  --stub-firebase  Before step 1, write COMPILE-ONLY Firebase stand-ins for a
                   checkout with no Firebase project — exactly what CI does
                   (build_runner must resolve firebase_module.dart's imports;
                   what was written is listed at the end):
                     * lib/firebase/firebase_options_<flavor>.dart for every
                       app with a lib/firebase/firebase_module.dart (one per
                       flavor it imports)
                     * android/app/src/<flavor>/google-services.json for every
                       app whose android/app applies the Google Services
                       plugin (package_name = applicationId + the flavor's
                       applicationIdSuffix)
                   Only files that are ABSENT are written; real ones are kept.
                   The app then compiles and builds, but nothing
                   Firebase-backed works (push, FCM token). Replace them with
                   `dart tools/firebase/firebase_config.dart --app <id>`.
  -h, --help       Print this help and exit.''';

void main(List<String> args) async {
  // Setup is destructive (step 2 cleans the workspace), so an argument this
  // script does not understand stops it before anything runs — `--help` used
  // to fall through into the full setup.
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    exit(0);
  }
  final stubFirebase = args.contains('--stub-firebase');
  final unknown = args.where((a) => a != '--stub-firebase').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('[ERROR] Unknown argument(s): ${unknown.join(' ')}');
    stderr.writeln('');
    stderr.writeln(_usage);
    exit(64);
  }

  // Every path below is relative to the repository root; resolve it from the
  // script's own location so the working directory does not matter.
  Directory.current = File.fromUri(Platform.script).parent.parent.parent;

  stdout.writeln('==========================================');
  stdout.writeln('      Project Configuration Setup');
  stdout.writeln('==========================================');

  // The same two-signal FVM detection every tool uses.
  reportToolchain();
  final flutterCmd = flutterExecutable;
  final dartCmd = dartExecutable;

  // --stub-firebase writes FIRST, before any codegen: build_runner reads
  // each app's firebase_module.dart, whose options imports must resolve —
  // CI always stubbed before this script for that reason. dart:io only, so
  // it needs nothing resolved. What was written is reported at the end,
  // where it cannot scroll away.
  FirebaseStubReport? stubs;
  if (stubFirebase) {
    stdout.writeln(
      '[!] Writing compile-only Firebase stubs (--stub-firebase) — '
      'summary at the end...',
    );
    stubs = writeFirebaseStubs('.');
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

  // 5. Code generation for the whole workspace — injectable, freezed,
  // json_serializable, retrofit, go_router_builder, drift. No generated file
  // is committed, so nothing past `pub get` compiles until this has run.
  stdout.writeln('[!] Running build_runner for the workspace...');
  await _runCommand(dartCmd, [
    ...dartArgs,
    'run',
    'build_runner',
    'build',
    '--workspace',
  ]);

  // 6. Write each package's one barrel (lib/<package>.dart). The generator
  // takes a single package lib/ and refuses anything else, so it runs once
  // per package.
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

  if (stubs != null) _reportFirebaseStubs(stubs);

  stdout.writeln('==========================================');
  stdout.writeln('[V] Configuration completed successfully!');
  stdout.writeln('==========================================');
}

/// `--stub-firebase`: what was stubbed, and a warning that cannot be
/// missed saying these are not real configs.
void _reportFirebaseStubs(FirebaseStubReport report) {
  stdout.writeln('[!] Firebase stubs (--stub-firebase):');
  for (final path in report.kept) {
    stdout.writeln('    - kept existing $path');
  }
  for (final path in report.written) {
    stdout.writeln('    - stubbed $path');
  }
  for (final note in report.notes) {
    stdout.writeln('    - $note');
  }
  if (report.written.isEmpty) {
    stdout.writeln('    Nothing to stub: every Firebase file already exists.');
    return;
  }
  stdout.writeln('');
  stdout.writeln(
    '  ************************************************************',
  );
  stdout.writeln(
    '  * ${report.written.length} Firebase file(s) above are STUBS, not real configs.',
  );
  stdout.writeln(
    '  * The app compiles and builds; push notifications, the FCM',
  );
  stdout.writeln(
    '  * token and every other Firebase call do NOT work. Replace',
  );
  stdout.writeln('  * them with a real project before relying on any of it:');
  stdout.writeln('  *   dart tools/firebase/firebase_config.dart --app <id>');
  stdout.writeln('  * (docs/en/getting-started/01_setup.md section 3.1)');
  stdout.writeln(
    '  ************************************************************',
  );
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
