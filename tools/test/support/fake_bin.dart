import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A directory of fake executables, put first on `PATH`.
///
/// The tools that shell out to `dart` / `flutter` (`configure`, `check_outdated`,
/// `theme_setting`) are exercised without a real toolchain, a network or a
/// pub cache: each fake is a tiny POSIX shell script that logs how it was
/// called (working directory and arguments, one line per call, to [log]) and
/// then does whatever the test scripted. The tool under test finds it exactly
/// the way it finds the real one — by name, through `PATH`.
///
/// POSIX only: callers skip on Windows ([skipWithoutPosixShell]).
class FakeBin {
  FakeBin._(this.dir, this.log);

  /// Where the fakes live.
  final String dir;

  /// One line per fake invocation: `<command> <cwd> <args…>`.
  final File log;

  /// Creates [scripts] (command name -> shell body, run by `/bin/sh`) in a
  /// temp directory removed when the current test ends. Every call is logged
  /// before the body runs.
  static FakeBin create(Map<String, String> scripts) {
    final root = Directory.systemTemp.createTempSync('fake_bin_');
    final dir = p.join(
      p.normalize(root.resolveSymbolicLinksSync()),
      'bin',
    );
    Directory(dir).createSync();
    final log = File(p.join(p.dirname(dir), 'calls.log'))..createSync();
    for (final entry in scripts.entries) {
      final file = File(p.join(dir, entry.key));
      file.writeAsStringSync(
        '#!/bin/sh\n'
        // `pwd -P` asks the kernel: a parent that chdir()s without exporting
        // PWD (the tools do `Directory.current = …`) leaves `$PWD` stale.
        'echo "${entry.key} \$(pwd -P) \$*" >> "${log.path}"\n'
        '${entry.value}\n',
      );
      Process.runSync('chmod', ['+x', file.path]);
    }
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    return FakeBin._(dir, log);
  }

  /// The environment that puts the fakes in front of the real `PATH`.
  Map<String, String> get environment => {
    'PATH':
        '$dir${Platform.isWindows ? ';' : ':'}${Platform.environment['PATH'] ?? ''}',
  };

  /// The logged calls, oldest first.
  List<String> get calls =>
      log.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

  /// The logged calls of [command], arguments only (the working directory is
  /// dropped), oldest first.
  List<String> argsOf(String command) => [
    for (final call in calls)
      if (call.startsWith('$command ')) call.split(' ').skip(2).join(' '),
  ];
}

/// A `skip:` value for tests that need `/bin/sh` scripts on `PATH`.
Object skipWithoutPosixShell() =>
    Platform.isWindows ? 'needs POSIX shell scripts on PATH' : false;
