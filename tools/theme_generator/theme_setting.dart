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
const _usage = '''
Usage: dart tools/theme_generator/theme_setting.dart [--app <id>]

Runs flutter_native_splash and icons_launcher for one app, with the
flutter_native_splash-<flavor>.yaml / icons_launcher-<flavor>.yaml configs at
the repository root (flavors dev, staging, prod).

Options:
  --app <id>   The app to generate for. Required when the workspace holds more
               than one app.
  -h, --help   Show this help.

The app needs android/ and ios/ (the configs enable both platforms) and must
declare flutter_native_splash and icons_launcher in its pubspec.yaml. If a
generator fails, every file it created or changed under android/, ios/ and
web/ is restored.''';

/// Platform directories the generators write into — snapshotted, so a failed
/// run leaves none of its output behind.
const _platformDirs = ['android', 'ios', 'web'];

/// Build output and tool caches inside those directories, never snapshotted.
const _skipDirs = {'build', '.gradle', 'Pods', '.dart_tool', '.symlinks'};

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--app') {
      i++; // its value; selectApp validates it
      continue;
    }
    stderr.writeln('[ERROR] Unknown argument: ${args[i]}');
    stderr.writeln(_usage);
    exit(64);
  }

  stdout.writeln('==========================================');
  stdout.writeln('       Theme and Asset Generator');
  stdout.writeln('==========================================');

  final app = selectApp(args);
  final appPath = app.dir;

  // Everything the generators need, checked before anything is written.
  // An app without android/ used to crash icons_launcher with a
  // PathNotFoundException halfway through, leaving PNGs behind.
  final problems = <String>[
    for (final platform in const ['android', 'ios'])
      if (!Directory('$appPath/$platform').existsSync())
        '$appPath/$platform/ does not exist — the configs enable $platform. '
            'Create it with `flutter create --platforms=android,ios .` in '
            '$appPath, or generate for an app that has it.',
  ];
  final pubspec = File('$appPath/pubspec.yaml');
  final pubspecText = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
  for (final package in const ['flutter_native_splash', 'icons_launcher']) {
    if (!RegExp('^\\s+$package:', multiLine: true).hasMatch(pubspecText)) {
      problems.add(
        '$appPath/pubspec.yaml does not declare $package — add it to '
        'dev_dependencies (the version comes from pubspec_dependencies.yaml).',
      );
    }
  }
  final configFiles = Directory.current.listSync().whereType<File>().where((
    file,
  ) {
    final name = file.uri.pathSegments.last;
    return name.startsWith('flutter_native_splash-') ||
        name.startsWith('icons_launcher-');
  }).toList();
  if (configFiles.isEmpty) {
    problems.add(
      'No flutter_native_splash-*.yaml / icons_launcher-*.yaml at the '
      'repository root. Run this from the repository root.',
    );
  }
  if (problems.isNotEmpty) {
    stderr.writeln('[ERROR] Cannot generate splash and icons for "${app.id}":');
    for (final problem in problems) {
      stderr.writeln('  - $problem');
    }
    exit(1);
  }

  reportToolchain();
  final dartCmd = dartExecutable;

  // Configs copied into the app for the generators, removed afterwards even
  // when a generator fails — otherwise they are left behind in apps/<id>/.
  final copied = <File>[];
  final snapshot = _snapshot(appPath);
  final dirsBefore = _platformDirsOnDisk(appPath);

  try {
    // 1. Copy config files to app directory
    stdout.writeln('[!] Copying configuration files to $appPath/...');
    for (final file in configFiles) {
      copied.add(file.copySync('$appPath/${file.uri.pathSegments.last}'));
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
    stderr.writeln(
      '[!] Restoring ${_platformDirs.map((d) => '$appPath/$d/').join(', ')}...',
    );
    _restore(appPath, snapshot, dirsBefore);
    exitCode = 1;
  } finally {
    stdout.writeln('[!] Cleaning up temporary configuration files...');
    for (final file in copied) {
      if (file.existsSync()) file.deleteSync();
    }
  }
}

/// Every file under the app's platform directories, with its bytes.
Map<String, List<int>> _snapshot(String appPath) => {
  for (final file in _platformFiles(appPath)) file.path: file.readAsBytesSync(),
};

/// Deletes files a failed run created, rewrites the ones it changed, and
/// removes directories it left empty.
void _restore(
  String appPath,
  Map<String, List<int>> snapshot,
  Set<String> dirsBefore,
) {
  for (final file in _platformFiles(appPath)) {
    final original = snapshot[file.path];
    try {
      if (original == null) {
        file.deleteSync();
      } else if (!_sameBytes(original, file.readAsBytesSync())) {
        file.writeAsBytesSync(original);
      }
    } on FileSystemException catch (e) {
      stderr.writeln('  ! could not restore ${file.path}: ${e.message}');
    }
  }
  for (final path in snapshot.keys) {
    final file = File(path);
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(snapshot[path]!);
    }
  }
  // Deepest first, so a new tree empties from its leaves up.
  final created = _platformDirsOnDisk(appPath).difference(dirsBefore).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final path in created) {
    final dir = Directory(path);
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }
}

/// The platform directories themselves and every directory below them.
Set<String> _platformDirsOnDisk(String appPath) => {
  for (final dir in _platformDirs)
    if (Directory('$appPath/$dir').existsSync()) ...[
      '$appPath/$dir',
      ..._walkDirs(Directory('$appPath/$dir')),
    ],
};

Iterable<String> _walkDirs(Directory dir) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is Directory && !_skipDirs.contains(_name(entity))) {
      yield entity.path;
      yield* _walkDirs(entity);
    }
  }
}

String _name(FileSystemEntity e) =>
    e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

Iterable<File> _platformFiles(String appPath) sync* {
  for (final dir in _platformDirs) {
    final root = Directory('$appPath/$dir');
    if (root.existsSync()) yield* _walk(root);
  }
}

Iterable<File> _walk(Directory dir) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is Directory) {
      if (_skipDirs.contains(
        entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      )) {
        continue;
      }
      yield* _walk(entity);
    } else if (entity is File) {
      yield entity;
    }
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
