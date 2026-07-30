import 'dart:convert'; // For utf8 decoding
import 'dart:io'; // For Process, exit, stdout, stderr

import 'output_formatter.dart';

// --- Configuration ---
final scriptsToRun = <Map<String, String>>[
  {
    'name': 'check_unused_assets.dart',
    'description': 'Unused Assets Detector',
    'icon': '🖼️',
  },
  {
    'name': 'check_unused_translate.dart',
    'description': 'Unused Translations Detector',
    'icon': '🌐',
  },
  {
    'name': 'check_unused_file.dart',
    'description': 'Unused Files Detector',
    'icon': '📄',
  },
  {
    'name': 'check_unused_packages.dart',
    'description': 'Unused Packages Detector',
    'icon': '📦',
  },
];
// --- End Configuration ---

/// Runs a single check script and handles its output.
/// Returns the exit code of the script.
Future<int> _runCheckScript(Map<String, String> scriptInfo) async {
  final scriptName = scriptInfo['name']!;
  final description = scriptInfo['description']!;
  final icon = scriptInfo['icon']!;
  final scriptPath = 'tools/unused_checker/$scriptName';

  OutputFormatter.printSection(description, icon: icon);
  OutputFormatter.printCommand(Platform.executable, ['run', scriptPath]);

  final stopwatch = Stopwatch()..start();

  final process = await Process.start(Platform.executable, [
    'run',
    scriptPath,
  ], mode: ProcessStartMode.normal);

  // Collect output for better formatting
  final outputLines = <String>[];
  final errorLines = <String>[];

  final stdoutSub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        outputLines.add(line);
        // Print with prefix for real-time feedback
        stdout.writeln('  📝 $line');
      });

  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        errorLines.add(line);
        OutputFormatter.printError(line, icon: '🚨');
      });

  final exitCode = await process.exitCode;
  stopwatch.stop();

  // Ensure streams are closed before proceeding
  await stdoutSub.cancel();
  await stderrSub.cancel();

  // Print result summary
  if (exitCode == 0) {
    OutputFormatter.printSuccess('$description completed successfully');
  } else if (exitCode == 2) {
    OutputFormatter.printWarning('$description completed with warnings');
  } else {
    OutputFormatter.printError('$description failed (Exit Code: $exitCode)');
    if (errorLines.isNotEmpty) {
      OutputFormatter.printBox('Error Details', errorLines, color: 'red');
    }
  }

  OutputFormatter.printTiming(description, stopwatch.elapsed);
  OutputFormatter.printSeparator();

  return exitCode;
}

void main() async {
  OutputFormatter.printHeader(
    'Flutter Project Unused Resources Checker',
    subtitle:
        'Comprehensive analysis of unused assets, files, packages, and translations',
  );

  final overallStopwatch = Stopwatch()..start();
  final List<Map<String, String>> failedScripts = [];
  final List<Map<String, String>> successfulScripts = [];
  final List<Map<String, String>> warningScripts = [];

  OutputFormatter.printInfo(
    'Starting analysis of ${scriptsToRun.length} check tools...',
  );
  OutputFormatter.printProgress(
    'Initializing',
    current: 0,
    total: scriptsToRun.length,
  );

  for (int i = 0; i < scriptsToRun.length; i++) {
    final scriptInfo = scriptsToRun[i];

    OutputFormatter.printProgress(
      'Running ${scriptInfo['description']}',
      current: i + 1,
      total: scriptsToRun.length,
    );

    final exitCode = await _runCheckScript(scriptInfo);

    if (exitCode == 0) {
      successfulScripts.add(scriptInfo);
    } else if (exitCode == 2) {
      warningScripts.add(scriptInfo);
      OutputFormatter.printWarning(
        'Check found warnings: ${scriptInfo['description']}',
      );
    } else {
      failedScripts.add(scriptInfo);
      OutputFormatter.printError('Check failed: ${scriptInfo['description']}');
      // Continue with other checks instead of stopping
    }
  }

  overallStopwatch.stop();

  // Print comprehensive summary
  final stats = {
    'Total Checks': scriptsToRun.length,
    'Successful': successfulScripts.length,
    'Warnings': warningScripts.length,
    'Failed': failedScripts.length,
    'Duration': '${overallStopwatch.elapsed.inMilliseconds}ms',
  };

  OutputFormatter.printStats(stats);

  if (failedScripts.isEmpty) {
    OutputFormatter.printFinalResult(
      success: true,
      message: warningScripts.isEmpty
          ? 'All checks passed! Your project is clean.'
          : 'All checks passed, but some have warnings. Please review the issues above.',
      stats: stats,
    );

    if (warningScripts.isNotEmpty) {
      OutputFormatter.printSummary(
        title: 'Warnings Found',
        items: warningScripts
            .map((s) => '${s['icon']} ${s['description']}')
            .toList(),
        isSuccess: false,
      );
    }

    // Show successful checks
    if (successfulScripts.isNotEmpty) {
      OutputFormatter.printSummary(
        title: 'Successful Checks',
        items: successfulScripts
            .map((s) => '${s['icon']} ${s['description']}')
            .toList(),
        isSuccess: true,
      );
    }

    exit(0);
  } else {
    OutputFormatter.printFinalResult(
      success: false,
      message: 'Some checks failed. Please review the issues above.',
      stats: stats,
    );

    // Show failed checks
    OutputFormatter.printSummary(
      title: 'Failed Checks',
      items: failedScripts
          .map((s) => '${s['icon']} ${s['description']}')
          .toList(),
      isSuccess: false,
    );

    if (warningScripts.isNotEmpty) {
      OutputFormatter.printSummary(
        title: 'Warnings Found',
        items: warningScripts
            .map((s) => '${s['icon']} ${s['description']}')
            .toList(),
        isSuccess: false,
      );
    }

    // Show successful checks if any
    if (successfulScripts.isNotEmpty) {
      OutputFormatter.printSummary(
        title: 'Successful Checks',
        items: successfulScripts
            .map((s) => '${s['icon']} ${s['description']}')
            .toList(),
        isSuccess: true,
      );
    }

    OutputFormatter.printInfo(
      '💡 Tip: Run individual checkers to get detailed information about specific issues.',
    );

    exit(1);
  }
}
