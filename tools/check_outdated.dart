import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'shared/toolchain.dart';

const _usage = '''
Usage: dart tools/check_outdated.dart

Resolves every package in pubspec_dependencies.yaml in a sandbox, runs
`pub outdated`, then offers a checklist to bump the catalog (on a terminal;
report only otherwise) and re-runs dependency_sync + pub get.

Exits non-zero when resolution, `pub outdated` or applying an update fails.''';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  if (args.isNotEmpty) {
    stderr.writeln('❌ Unknown argument(s): ${args.join(' ')}');
    stderr.writeln(_usage);
    exit(64);
  }

  final stopwatch = Stopwatch()..start();

  stdout.writeln(
    '================================================================',
  );
  stdout.writeln('📦 Outdated Dependencies Checker for Monorepo Workspace');
  stdout.writeln(
    '================================================================',
  );

  final projectRoot = Directory.current.path;
  final dependenciesFile = File(
    p.join(projectRoot, 'pubspec_dependencies.yaml'),
  );

  if (!dependenciesFile.existsSync()) {
    stderr.writeln(
      '❌ Error: pubspec_dependencies.yaml not found at root: $projectRoot',
    );
    exit(1);
  }

  final sandboxDir = Directory(
    p.join(projectRoot, '.dart_tool', 'outdated_check'),
  );

  try {
    // 1. Create the sandbox
    stdout.writeln('⏳ Preparing temporary sandbox...');
    if (sandboxDir.existsSync()) {
      sandboxDir.deleteSync(recursive: true);
    }
    sandboxDir.createSync(recursive: true);

    // 2. Rebuild a pubspec from the catalog
    final pubspecFile = File(p.join(sandboxDir.path, 'pubspec.yaml'));
    final dependenciesContent = dependenciesFile.readAsStringSync();

    // Add the minimum metadata that makes it a valid pubspec
    final dummyPubspecContent =
        '''
name: outdated_check
description: A temporary pubspec to check outdated shared dependencies.
publish_to: 'none'
environment:
  sdk: '>=3.13.3 <4.0.0'
  flutter: ">=3.47.4"

$dependenciesContent
''';

    pubspecFile.writeAsStringSync(dummyPubspecContent);

    // The repo's toolchain — `fvm dart` when FVM is configured and
    // installed — never whichever SDK happens to run this script.
    reportToolchain();
    final executable = dartExecutable;
    final getArgs = [...dartArgs, 'pub', 'get'];
    final outdatedArgs = [...dartArgs, 'pub', 'outdated'];

    stdout.writeln('⏳ Resolving dependencies (this might take a moment)...\n');

    // 3. Run pub get (output hidden unless it fails)
    final getResult = await Process.run(
      executable,
      getArgs,
      workingDirectory: sandboxDir.path,
      runInShell: true,
    );

    if (getResult.exitCode != 0) {
      stderr.writeln('❌ Failed to resolve dependencies in sandbox!');
      stderr.writeln(getResult.stderr);
      // Not `exit(1)`: that would skip the `finally` below that deletes the
      // sandbox directory.
      exitCode = 1;
      return;
    }

    // 4. Run pub outdated (stdout passed through to keep its colours)
    final outdatedProcess = await Process.start(
      executable,
      outdatedArgs,
      workingDirectory: sandboxDir.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );

    final outdatedExit = await outdatedProcess.exitCode;

    if (outdatedExit == 0) {
      stdout.writeln(
        '\n✅ Outdated check completed successfully in ${stopwatch.elapsedMilliseconds}ms.',
      );

      stdout.writeln('\n⏳ Fetching latest versions data for checklist...');
      final jsonProcess = await Process.run(
        executable,
        [...outdatedArgs, '--json'],
        workingDirectory: sandboxDir.path,
        runInShell: true,
      );

      if (jsonProcess.exitCode == 0) {
        try {
          final data =
              jsonDecode(jsonProcess.stdout as String) as Map<String, dynamic>;
          final packages = data['packages'] as List<dynamic>? ?? [];

          String depsContent = dependenciesFile.readAsStringSync();
          final List<Map<String, dynamic>> outdatedList = [];

          for (final pkg in packages.cast<Map<String, dynamic>>()) {
            final name = pkg['package'] as String?;
            final latest =
                (pkg['latest'] as Map<String, dynamic>?)?['version'] as String?;

            if (name != null && latest != null) {
              final regex = RegExp(
                '^(\\s*$name\\s*:\\s*["\']?\\^?)([^"\']+)(["\']?)',
                multiLine: true,
              );
              final match = regex.firstMatch(depsContent);
              if (match != null) {
                final currentVersion = match.group(2);
                if (currentVersion != latest) {
                  outdatedList.add({
                    'name': name,
                    'current': currentVersion,
                    'latest': latest,
                    'selected': true,
                    'regex': regex,
                  });
                }
              }
            }
          }

          if (outdatedList.isEmpty) {
            stdout.writeln(
              '\n✨ All packages in pubspec_dependencies.yaml are already at their latest versions!',
            );
          } else if (!stdin.hasTerminal) {
            // No one to ask (CI, a pipe): report only. Applying on EOF would
            // bump every package — major versions included — unattended.
            stdout.writeln(
              '\n📦 Outdated packages (report only, no terminal):',
            );
            for (final item in outdatedList) {
              stdout.writeln(
                '  - ${item['name']} (${item['current']} -> ${item['latest']})',
              );
            }
          } else {
            // Interactive checklist loop
            bool proceed = false;
            while (true) {
              stdout.writeln('\n📦 Outdated Packages Checklist:');
              for (int i = 0; i < outdatedList.length; i++) {
                final item = outdatedList[i];
                final checkbox = (item['selected'] as bool) ? '[x]' : '[ ]';
                stdout.writeln(
                  '  $checkbox ${i + 1}. ${item['name']} (${item['current']} -> ${item['latest']})',
                );
              }

              stdout.writeln('\nOptions:');
              stdout.writeln(
                '  - Type numbers separated by comma (e.g. 1,3) to TOGGLE selection',
              );
              stdout.writeln('  - Type "all" to select all');
              stdout.writeln('  - Type "none" to deselect all');
              stdout.writeln('  - Type "a" to APPLY selected updates');
              stdout.writeln('  - Type "q" to QUIT without making changes');

              stdout.write('\nYour choice: ');
              final line = stdin.readLineSync();
              if (line == null) {
                stdout.writeln('\nAborted (end of input).');
                break;
              }
              final input = line.trim().toLowerCase();

              if (input.isEmpty) {
                continue;
              } else if (input == 'q') {
                stdout.writeln('\nAborted.');
                break;
              } else if (input == 'a') {
                proceed = true;
                break;
              } else if (input == 'all') {
                for (var item in outdatedList) {
                  item['selected'] = true;
                }
              } else if (input == 'none') {
                for (var item in outdatedList) {
                  item['selected'] = false;
                }
              } else {
                final parts = input.split(',');
                for (final p in parts) {
                  final num = int.tryParse(p.trim());
                  if (num != null && num > 0 && num <= outdatedList.length) {
                    final idx = num - 1;
                    outdatedList[idx]['selected'] =
                        !(outdatedList[idx]['selected'] as bool);
                  }
                }
              }
            }

            if (proceed) {
              int updateCount = 0;
              for (final item in outdatedList) {
                if (item['selected'] as bool) {
                  final regex = item['regex'] as RegExp;
                  depsContent = depsContent.replaceAllMapped(regex, (match) {
                    return '${match.group(1)}${item['latest']}${match.group(3)}';
                  });
                  updateCount++;
                  stdout.writeln(
                    '⬆️  Updated ${item['name']}: ${item['current']} -> ${item['latest']}',
                  );
                }
              }

              if (updateCount > 0) {
                dependenciesFile.writeAsStringSync(depsContent);
                stdout.writeln(
                  '\n✅ Successfully updated $updateCount packages in pubspec_dependencies.yaml!',
                );

                stdout.writeln('\n🔄 Auto-syncing workspace dependencies...');
                final syncProcess = await Process.start(
                  executable,
                  [...dartArgs, 'tools/dependency_sync.dart'],
                  workingDirectory: projectRoot,
                  mode: ProcessStartMode.inheritStdio,
                  runInShell: true,
                );

                if (await syncProcess.exitCode == 0) {
                  stdout.writeln('\n🚀 Running pub get to apply changes...');
                  final pubGetProcess = await Process.start(
                    executable,
                    getArgs,
                    workingDirectory: projectRoot,
                    mode: ProcessStartMode.inheritStdio,
                    runInShell: true,
                  );

                  if (await pubGetProcess.exitCode == 0) {
                    stdout.writeln(
                      '\n🎉 All done! Workspace is fully up-to-date.',
                    );
                  } else {
                    stderr.writeln('\n⚠️ pub get finished with errors.');
                    exitCode = 1;
                  }
                } else {
                  stderr.writeln('\n❌ Workspace synchronization failed.');
                  exitCode = 1;
                }
              } else {
                stdout.writeln('\n⚠️ No packages were selected for update.');
              }
            }
          }
        } catch (e) {
          stderr.writeln('❌ Failed to parse JSON from pub outdated: $e');
          exitCode = 1;
        }
      } else {
        stderr.writeln('❌ Error running pub outdated --json.');
        stderr.writeln(jsonProcess.stderr);
        exitCode = 1;
      }
    } else {
      stderr.writeln('\n❌ Outdated check finished with code: $outdatedExit');
      exitCode = 1;
    }
  } catch (e, stackTrace) {
    stderr.writeln('❌ An unexpected error occurred:');
    stderr.writeln(e);
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    // 5. Clean up
    try {
      if (sandboxDir.existsSync()) {
        // Pause briefly before deleting so Windows releases its file handles
        await Future<void>.delayed(const Duration(milliseconds: 200));
        sandboxDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Ignore deletion errors on Windows if files are still locked
    }
  }
}
