import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

void main() async {
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
    // 1. Khởi tạo Sandbox
    stdout.writeln('⏳ Preparing temporary sandbox...');
    if (sandboxDir.existsSync()) {
      sandboxDir.deleteSync(recursive: true);
    }
    sandboxDir.createSync(recursive: true);

    // 2. Tái tạo Pubspec
    final pubspecFile = File(p.join(sandboxDir.path, 'pubspec.yaml'));
    final dependenciesContent = dependenciesFile.readAsStringSync();

    // Gắn thêm meta data tối thiểu để thành file pubspec hợp lệ
    final dummyPubspecContent =
        '''
name: outdated_check
description: A temporary pubspec to check outdated shared dependencies.
publish_to: 'none'
environment:
  sdk: '>=3.13.0 <4.0.0'
  flutter: ">=3.47.0"

$dependenciesContent
''';

    pubspecFile.writeAsStringSync(dummyPubspecContent);

    // Sử dụng Platform.resolvedExecutable để luôn dùng đúng phiên bản Dart SDK đang chạy script này
    final executable = Platform.resolvedExecutable;
    final getArgs = ['pub', 'get'];
    final outdatedArgs = ['pub', 'outdated'];

    stdout.writeln('⏳ Resolving dependencies (this might take a moment)...\n');

    // 3. Chạy pub get (ẩn log trừ khi lỗi)
    final getResult = await Process.run(
      executable,
      getArgs,
      workingDirectory: sandboxDir.path,
    );

    if (getResult.exitCode != 0) {
      stderr.writeln('❌ Failed to resolve dependencies in sandbox!');
      stderr.writeln(getResult.stderr);
      exit(1);
    }

    // 4. Chạy pub outdated (truyền thẳng stdout để giữ màu)
    final outdatedProcess = await Process.start(
      executable,
      outdatedArgs,
      workingDirectory: sandboxDir.path,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await outdatedProcess.exitCode;

    if (exitCode == 0) {
      stdout.writeln(
        '\n✅ Outdated check completed successfully in ${stopwatch.elapsedMilliseconds}ms.',
      );

      stdout.writeln('\n⏳ Fetching latest versions data for checklist...');
      final jsonProcess = await Process.run(executable, [
        'pub',
        'outdated',
        '--json',
      ], workingDirectory: sandboxDir.path);

      if (jsonProcess.exitCode == 0) {
        try {
          final Map<String, dynamic> data = jsonDecode(jsonProcess.stdout);
          final packages = data['packages'] as List<dynamic>? ?? [];

          String depsContent = dependenciesFile.readAsStringSync();
          final List<Map<String, dynamic>> outdatedList = [];

          for (final pkg in packages) {
            final name = pkg['package'] as String?;
            final latest = pkg['latest']?['version'] as String?;

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
              stdout.writeln(
                '  - Type "a" (or press Enter) to APPLY selected updates',
              );
              stdout.writeln('  - Type "q" to QUIT without making changes');

              stdout.write(
                '\nYour choice: (Empty to migrate all selected packages)',
              );
              final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';

              if (input == 'q') {
                stdout.writeln('\nAborted.');
                break;
              } else if (input == 'a' || input.isEmpty) {
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
                  ['tools/dependency_sync.dart'],
                  workingDirectory: projectRoot,
                  mode: ProcessStartMode.inheritStdio,
                );

                if (await syncProcess.exitCode == 0) {
                  stdout.writeln('\n🚀 Running pub get to apply changes...');
                  final pubGetProcess = await Process.start(
                    executable,
                    ['pub', 'get'],
                    workingDirectory: projectRoot,
                    mode: ProcessStartMode.inheritStdio,
                  );

                  if (await pubGetProcess.exitCode == 0) {
                    stdout.writeln(
                      '\n🎉 All done! Workspace is fully up-to-date.',
                    );
                  } else {
                    stderr.writeln('\n⚠️ pub get finished with errors.');
                  }
                } else {
                  stderr.writeln('\n❌ Workspace synchronization failed.');
                }
              } else {
                stdout.writeln('\n⚠️ No packages were selected for update.');
              }
            }
          }
        } catch (e) {
          stderr.writeln('❌ Failed to parse JSON from pub outdated: $e');
        }
      } else {
        stderr.writeln('❌ Error running pub outdated --json.');
      }
    } else {
      stderr.writeln('\n⚠️ Outdated check finished with code: $exitCode');
    }
  } catch (e, stackTrace) {
    stderr.writeln('❌ An unexpected error occurred:');
    stderr.writeln(e);
    stderr.writeln(stackTrace);
  } finally {
    // 5. Dọn dẹp
    try {
      if (sandboxDir.existsSync()) {
        // Nghỉ một chút trước khi xoá để nhả handle trên Windows
        await Future.delayed(const Duration(milliseconds: 200));
        sandboxDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Ignore deletion errors on Windows if files are still locked
    }
  }
}
