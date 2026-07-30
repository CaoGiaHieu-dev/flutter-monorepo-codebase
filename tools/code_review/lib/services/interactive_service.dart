import 'dart:io';
import '../core/constants.dart';

class InteractiveService {
  /// Run interactive mode to configure all options
  static Future<List<String>> runInteractiveMode() async {
    // ignore: avoid_print
    print('🤖 Welcome to Interactive Code Review Mode!');
    // ignore: avoid_print
    print('Let\'s configure your review settings step by step.\n');

    // Get review scope
    final scope = await promptReviewScope();

    // Get focus areas
    final focusAreas = await promptFocusAreas();

    // Get exclude patterns
    final excludePatterns = await promptExcludePatterns();

    // Get output options
    final outputOptions = await promptOutputOptions();

    // Get verbose mode
    final verbose = await promptVerboseMode();

    // Get report language
    final language = await promptReportLanguage();

    // Get output format
    final format = await promptOutputFormat();

    // Build arguments for the tool
    final args = <String>[];

    // Add scope arguments
    switch (scope['type']) {
      case 'all':
        args.add('--all');
        break;
      case 'folder':
        args.addAll(['--folder', scope['path']]);
        break;
      case 'files':
        for (final file in scope['files'] as List<String>) {
          args.addAll(['--file', file]);
        }
        break;
      case 'changed':
        args.add('--changed');
        break;
      case 'staged':
        args.add('--staged');
        break;
    }

    // Add focus areas
    if (focusAreas.isNotEmpty) {
      for (final area in focusAreas) {
        args.addAll(['--focus', area]);
      }
    }

    // Add exclude patterns
    if (excludePatterns.isNotEmpty) {
      for (final pattern in excludePatterns) {
        args.addAll(['--exclude', pattern]);
      }
    }

    // Add output options
    if (outputOptions['summary'] as bool) {
      args.add('--summary');
      args.addAll(['--output-dir', outputOptions['outputDir'] as String]);
    } else {
      args.add('--no-summary');
    }

    // Add verbose mode
    if (verbose) {
      args.add('--verbose');
    }

    // Add language and format arguments (these will be saved to config)
    args.addAll(['--language', language]);
    args.addAll(['--format', format]);

    // Show configuration summary
    // ignore: avoid_print
    print('\n📋 Configuration Summary:');
    // ignore: avoid_print
    print('• Scope: ${scope['description']}');
    if (focusAreas.isNotEmpty) {
      // ignore: avoid_print
      print('• Focus Areas: ${focusAreas.join(', ')}');
    }
    if (excludePatterns.isNotEmpty) {
      // ignore: avoid_print
      print('• Exclude Patterns: ${excludePatterns.join(', ')}');
    }
    // ignore: avoid_print
    print('• Generate Report: ${outputOptions['summary']}');
    if (outputOptions['summary'] as bool) {
      // ignore: avoid_print
      print('• Output Directory: ${outputOptions['outputDir']}');
    }
    // ignore: avoid_print
    print(
      '• Report Language: ${CodeReviewConstants.languageNames[language] ?? language}',
    );
    // ignore: avoid_print
    print('• Output Format: $format');
    // ignore: avoid_print
    print('• Verbose Mode: $verbose');
    // ignore: avoid_print
    print('');

    // Confirm and start review
    stdout.write('🚀 Start code review with these settings? (Y/n): ');
    final confirm = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';

    if (confirm == 'n' || confirm == 'no') {
      // ignore: avoid_print
      print('❌ Code review cancelled by user.');
      exit(0);
    }

    return args;
  }

  /// Prompt user for batch review preference
  static Future<bool> promptBatchReview(int fileCount) async {
    if (fileCount <= 1) return false;

    // ignore: avoid_print
    print('🚀 Review Mode Options:');
    // ignore: avoid_print
    print(
      '1. 🔥 Batch Review (FAST) - Review all $fileCount files in one API call',
    );
    // ignore: avoid_print
    print('2. 📄 Individual Review (DETAILED) - Review each file separately');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(
      '💡 Batch review is much faster but may have less detailed analysis per file.',
    );
    // ignore: avoid_print
    print(
      '💡 Individual review is slower but provides more detailed analysis per file.',
    );
    // ignore: avoid_print
    print('');

    stdout.write(
      'Choose review mode (1 for Batch, 2 for Individual, default: 1): ',
    );
    final choice = stdin.readLineSync()?.trim() ?? '1';

    return choice == '1' || choice.isEmpty;
  }

  /// Prompt for review scope
  static Future<Map<String, dynamic>> promptReviewScope() async {
    // ignore: avoid_print
    print('🎯 What would you like to review?');
    // ignore: avoid_print
    print('1. All Dart files in the project');
    // ignore: avoid_print
    print('2. Specific folder');
    // ignore: avoid_print
    print('3. Specific file(s)');
    // ignore: avoid_print
    print('4. Changed files (Git)');
    // ignore: avoid_print
    print('5. Staged files (Git)');
    // ignore: avoid_print
    print('');

    stdout.write('Choose option (1-5): ');
    final choice = stdin.readLineSync()?.trim() ?? '1';

    switch (choice) {
      case '1':
        return {'type': 'all', 'description': 'All Dart files'};

      case '2':
        stdout.write('📁 Enter folder path (e.g., lib/presentation): ');
        final folderPath = stdin.readLineSync()?.trim() ?? '';
        if (folderPath.isEmpty) {
          // ignore: avoid_print
          print('⚠️  No folder specified, using all files');
          return {'type': 'all', 'description': 'All Dart files'};
        }
        return {
          'type': 'folder',
          'path': folderPath,
          'description': 'Folder: $folderPath',
        };

      case '3':
        // ignore: avoid_print
        print('📄 Enter file paths (one per line, empty line to finish):');
        final files = <String>[];
        while (true) {
          stdout.write('File path: ');
          final filePath = stdin.readLineSync()?.trim() ?? '';
          if (filePath.isEmpty) break;
          files.add(filePath);
        }
        if (files.isEmpty) {
          // ignore: avoid_print
          print('⚠️  No files specified, using all files');
          return {'type': 'all', 'description': 'All Dart files'};
        }
        return {
          'type': 'files',
          'files': files,
          'description': '${files.length} specific file(s)',
        };

      case '4':
        return {'type': 'changed', 'description': 'Changed files (Git)'};

      case '5':
        return {'type': 'staged', 'description': 'Staged files (Git)'};

      default:
        // ignore: avoid_print
        print('⚠️  Invalid choice, using all files');
        return {'type': 'all', 'description': 'All Dart files'};
    }
  }

  /// Prompt for focus areas
  static Future<List<String>> promptFocusAreas() async {
    // ignore: avoid_print
    print('\n🔍 Focus Areas (optional):');
    // ignore: avoid_print
    print('Available focus areas:');
    // ignore: avoid_print
    print('1. security - Security vulnerabilities and data protection');
    // ignore: avoid_print
    print('2. performance - Performance bottlenecks and optimization');
    // ignore: avoid_print
    print('3. bugs - Potential runtime errors and logic bugs');
    // ignore: avoid_print
    print('4. style - Code style and formatting conventions');
    // ignore: avoid_print
    print('5. architecture - Design patterns and code organization');
    // ignore: avoid_print
    print('6. testing - Testability and test coverage');
    // ignore: avoid_print
    print('');

    stdout.write(
      'Select focus areas (comma-separated numbers, or Enter for all): ',
    );
    final input = stdin.readLineSync()?.trim() ?? '';

    if (input.isEmpty) {
      return [];
    }

    final focusMap = {
      '1': 'security',
      '2': 'performance',
      '3': 'bugs',
      '4': 'style',
      '5': 'architecture',
      '6': 'testing',
    };

    final selectedNumbers = input.split(',').map((s) => s.trim()).toList();
    final focusAreas = <String>[];

    for (final number in selectedNumbers) {
      if (focusMap.containsKey(number)) {
        focusAreas.add(focusMap[number]!);
      }
    }

    return focusAreas;
  }

  /// Prompt for exclude patterns
  static Future<List<String>> promptExcludePatterns() async {
    // ignore: avoid_print
    print('\n🚫 Exclude Patterns (optional):');
    // ignore: avoid_print
    print(
      'Default exclusions: *.g.dart, *.freezed.dart, *.mocks.dart, test/**',
    );
    // ignore: avoid_print
    print('');

    stdout.write('Add custom exclude patterns? (y/N): ');
    final addCustom = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';

    if (addCustom != 'y' && addCustom != 'yes') {
      return [];
    }

    // ignore: avoid_print
    print('Enter exclude patterns (one per line, empty line to finish):');
    // ignore: avoid_print
    print('Examples: **/*.generated.dart, lib/legacy/**, **/old_*.dart');

    final patterns = <String>[];
    while (true) {
      stdout.write('Pattern: ');
      final pattern = stdin.readLineSync()?.trim() ?? '';
      if (pattern.isEmpty) break;
      patterns.add(pattern);
    }

    return patterns;
  }

  /// Prompt for output options
  static Future<Map<String, dynamic>> promptOutputOptions() async {
    // ignore: avoid_print
    print('\n📊 Output Options:');

    stdout.write('Generate summary report? (Y/n): ');
    final generateSummary = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';
    final summary =
        generateSummary == 'y' ||
        generateSummary == 'yes' ||
        generateSummary == '';

    String outputDir = 'code_review_reports';
    if (summary) {
      stdout.write('Output directory (default: code_review_reports): ');
      final customDir = stdin.readLineSync()?.trim() ?? '';
      if (customDir.isNotEmpty) {
        outputDir = customDir;
      }
    }

    return {'summary': summary, 'outputDir': outputDir};
  }

  /// Prompt for verbose mode
  static Future<bool> promptVerboseMode() async {
    // ignore: avoid_print
    print('\n🔊 Verbose Mode:');
    stdout.write('Enable verbose output? (y/N): ');
    final verbose = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
    return verbose == 'y' || verbose == 'yes';
  }

  /// Prompt for report language
  static Future<String> promptReportLanguage() async {
    // ignore: avoid_print
    print('\n🌐 Report Language:');
    // ignore: avoid_print
    print('Available languages:');

    final languages = CodeReviewConstants.supportedLanguages;
    final languageNames = CodeReviewConstants.languageNames;

    for (int i = 0; i < languages.length; i++) {
      final lang = languages[i];
      final name = languageNames[lang] ?? lang;
      // ignore: avoid_print
      print('${i + 1}. $lang - $name');
    }
    // ignore: avoid_print
    print('');

    stdout.write(
      'Select language (1-${languages.length}, default: 2 for Vietnamese): ',
    );
    final input = stdin.readLineSync()?.trim() ?? '2';

    final index = int.tryParse(input);
    if (index != null && index >= 1 && index <= languages.length) {
      return languages[index - 1];
    }

    return 'en'; // Default to English
  }

  /// Prompt for output format
  static Future<String> promptOutputFormat() async {
    // ignore: avoid_print
    print('\n📄 Output Format:');
    // ignore: avoid_print
    print('1. markdown - Markdown format (.md)');
    // ignore: avoid_print
    print('2. html - HTML format (.html)');
    // ignore: avoid_print
    print('3. json - JSON format (.json)');
    // ignore: avoid_print
    print('4. txt - Plain text (.txt)');
    // ignore: avoid_print
    print('');

    stdout.write('Select format (1-4, default: 1 for Markdown): ');
    final input = stdin.readLineSync()?.trim() ?? '1';

    switch (input) {
      case '2':
        return 'html';
      case '3':
        return 'json';
      case '4':
        return 'txt';
      default:
        return 'markdown';
    }
  }
}
