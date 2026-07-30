import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'core/constants.dart';
import 'models/review_result.dart';
import 'services/api_key_service.dart';
import 'services/api_service.dart';
import 'services/batch_service.dart';
import 'services/config_service.dart';
import 'services/file_service.dart';
import 'services/interactive_service.dart';
import 'services/report_service.dart';
import 'utils/file_analyzer.dart';

/// Main Code Review Tool class with improved batch processing
class CodeReviewTool {
  late String _apiKey;
  late ArgResults _args;
  final List<ReviewResult> _reviewResults = [];
  late String _outputDir;
  late ApiService _apiService;
  late BatchService _batchService;

  /// Main entry point
  Future<void> run(List<String> arguments) async {
    final parser = _createArgParser();

    try {
      _args = parser.parse(arguments);
    } catch (e) {
      // ignore: avoid_print
      print('Error parsing arguments: $e');
      // ignore: avoid_print
      print(parser.usage);
      exit(1);
    }

    if (_args['help'] as bool) {
      _printHelp(parser);
      return;
    }

    if (_args['show-config'] as bool) {
      ConfigService.showConfig();
      return;
    }

    if (_args['config'] as bool) {
      await _runConfigMode();
      return;
    }

    // Check if interactive mode is requested or no specific options provided
    final fileList = _args['file'] as List<String>?;
    final hasSpecificOptions =
        (_args['all'] as bool) ||
        (fileList != null && fileList.isNotEmpty) ||
        _args['folder'] != null ||
        (_args['changed'] as bool) ||
        (_args['staged'] as bool);

    if ((_args['interactive'] as bool) || !hasSpecificOptions) {
      final interactiveArgs = await InteractiveService.runInteractiveMode();
      await run(interactiveArgs);
      return;
    }

    // Save language and format settings to config
    await _saveLanguageAndFormatSettings();

    // Get API key and initialize services
    _apiKey = ApiKeyService.getApiKey(_args);
    _apiService = ApiService(_apiKey);
    _batchService = BatchService(_apiService);

    // Initialize output directory
    _outputDir = _args['output-dir'] as String;

    // ignore: avoid_print
    print('🤖 Starting code review with Gemini AI...');
    // ignore: avoid_print
    print('📁 Working directory: ${Directory.current.path}');
    // ignore: avoid_print
    print('🔑 API Key: ${_apiKey.substring(0, 8)}...');
    if (_args['summary'] as bool) {
      // ignore: avoid_print
      print('📊 Summary will be saved to: $_outputDir/');
    }
    // ignore: avoid_print
    print('');

    // Validate we're in a Flutter project
    if (!await FileAnalyzer.validateFlutterProject()) {
      // ignore: avoid_print
      print('❌ This doesn\'t appear to be a Flutter project.');
      // ignore: avoid_print
      print('💡 Please run this tool from the root of your Flutter project.');
      exit(1);
    }

    // Get files to review based on options
    final filesToReview = await _getFilesToReview();

    if (filesToReview.isEmpty) {
      // ignore: avoid_print
      print('📝 No files found to review.');
      return;
    }

    // ignore: avoid_print
    print('📋 Found ${filesToReview.length} file(s) to review:\n');
    for (final file in filesToReview) {
      // ignore: avoid_print
      print('  • $file');
    }
    // ignore: avoid_print
    print('');

    // Ask user for batch review preference
    final useBatchReview = await _promptBatchReview(filesToReview.length);

    if (useBatchReview) {
      await _reviewFilesBatch(filesToReview);
    } else {
      // Review each file individually
      for (final filePath in filesToReview) {
        await _reviewFile(filePath);
        // ignore: avoid_print
        print(''); // Add spacing between files
      }
    }

    // Generate summary report if enabled
    if (_args['summary'] as bool && _reviewResults.isNotEmpty) {
      await ReportService.generateSummaryReport(
        reviewResults: _reviewResults,
        outputDir: _outputDir,
      );
    }

    // ignore: avoid_print
    print('✅ Code review completed!');
  }

  /// Create argument parser
  ArgParser _createArgParser() {
    return ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        help: 'Show help information',
        negatable: false,
      )
      ..addFlag(
        'all',
        abbr: 'a',
        help: 'Review all Dart files in the project',
        negatable: false,
      )
      ..addMultiOption('file', abbr: 'f', help: 'Review specific file(s)')
      ..addOption(
        'folder',
        help:
            'Review all Dart files in specific folder (e.g., lib/presentation)',
      )
      ..addFlag(
        'changed',
        abbr: 'c',
        help: 'Review files changed in git (unstaged + staged)',
        negatable: false,
      )
      ..addFlag(
        'staged',
        abbr: 's',
        help: 'Review files staged for commit',
        negatable: false,
      )
      ..addOption(
        'api-key',
        help: 'Gemini API key (or set GEMINI_API_KEY env var)',
      )
      ..addMultiOption('exclude', help: 'Exclude files matching pattern (glob)')
      ..addFlag('verbose', abbr: 'v', help: 'Verbose output', negatable: false)
      ..addMultiOption(
        'focus',
        help: 'Focus review on specific aspects',
        allowed: CodeReviewConstants.focusAreas,
      )
      ..addFlag(
        'summary',
        help: 'Generate summary report file',
        defaultsTo: true,
      )
      ..addOption(
        'output-dir',
        help: 'Output directory for summary report',
        defaultsTo: CodeReviewConstants.defaultOutputDir,
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        help: 'Interactive mode to configure all options',
        negatable: false,
      )
      ..addOption(
        'language',
        help: 'Report language (en, vi, ja, ko, zh, fr, de, es)',
        allowed: CodeReviewConstants.supportedLanguages,
        defaultsTo: 'en',
      )
      ..addOption(
        'format',
        help: 'Output format (markdown, html, json, txt)',
        allowed: ['markdown', 'html', 'json', 'txt'],
        defaultsTo: 'markdown',
      )
      ..addFlag(
        'show-config',
        help: 'Show current configuration settings',
        negatable: false,
      )
      ..addFlag(
        'config',
        help: 'Configure tool settings interactively',
        negatable: false,
      );
  }

  /// Print help information
  void _printHelp(ArgParser parser) {
    // ignore: avoid_print
    print('🤖 Code Review Tool using Gemini AI\n');
    // ignore: avoid_print
    print('Usage: dart tools/code_review/code_review.dart [options]\n');
    // ignore: avoid_print
    print('Options:');
    // ignore: avoid_print
    print(parser.usage);
    // ignore: avoid_print
    print('\n📚 Examples:');
    // ignore: avoid_print
    print('  # Interactive mode (default - configure all options)');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart\n');
    // ignore: avoid_print
    print('  # Review all Dart files');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart --all\n');
    // ignore: avoid_print
    print('  # Review specific file');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart --file lib/main.dart\n');
    // ignore: avoid_print
    print('  # Review specific folder');
    // ignore: avoid_print
    print(
      '  dart tools/code_review/code_review.dart --folder lib/presentation\n',
    );
    // ignore: avoid_print
    print('  # Review changed files in Git');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart --changed\n');
    // ignore: avoid_print
    print('  # Review staged files');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart --staged\n');
    // ignore: avoid_print
    print('  # Focus on specific aspects');
    // ignore: avoid_print
    print('  dart tools/code_review/code_review.dart --focus security,bugs\n');
    // ignore: avoid_print
    print('  # Exclude generated files');
    // ignore: avoid_print
    print(
      '  dart tools/code_review/code_review.dart --exclude "**/*.g.dart"\n',
    );
    // ignore: avoid_print
    print('  # With API key and custom output');
    // ignore: avoid_print
    print(
      '  dart tools/code_review/code_review.dart --api-key "your_key" --all --output-dir reports\n',
    );
    // ignore: avoid_print
    print('🔑 API Key Setup:');
    // ignore: avoid_print
    print('  1. Environment variable: export GEMINI_API_KEY="your_key"');
    // ignore: avoid_print
    print('  2. Command line: --api-key "your_key"');
    // ignore: avoid_print
    print('  3. Config file: Add "geminiApiKey" to code_review_config.json');
    // ignore: avoid_print
    print('  4. Interactive prompt: Tool will ask if no key is found');
    // ignore: avoid_print
    print('  Get your key at: https://makersuite.google.com/app/apikey');
  }

  /// Get list of files to review based on arguments
  Future<List<String>> _getFilesToReview() async {
    return FileService.getFilesToReview(
      reviewAll: _args['all'] as bool,
      specificFiles: _args['file'] as List<String>? ?? [],
      folderPath: _args['folder'] as String?,
      reviewChanged: _args['changed'] as bool,
      reviewStaged: _args['staged'] as bool,
      excludePatterns: _args['exclude'] as List<String>? ?? [],
    );
  }

  /// Prompt user for batch review preference
  Future<bool> _promptBatchReview(int fileCount) async {
    if (fileCount <= 1) return false;

    // ignore: avoid_print
    print('🚀 Review Mode Options:');
    // ignore: avoid_print
    print(
      '1. 🔥 Batch Review (FAST) - Review all $fileCount files concurrently',
    );
    // ignore: avoid_print
    print('2. 📄 Individual Review (DETAILED) - Review each file separately');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(
      '💡 Batch review processes files in parallel with real-time feedback.',
    );
    // ignore: avoid_print
    print(
      '💡 Individual review is slower but provides more detailed console output.',
    );
    // ignore: avoid_print
    print('');

    stdout.write(
      'Choose review mode (1 for Batch, 2 for Individual, default: 1): ',
    );
    final choice = stdin.readLineSync()?.trim() ?? '1';

    return choice == '1' || choice.isEmpty;
  }

  /// Review files in batch mode using BatchService
  Future<void> _reviewFilesBatch(List<String> filePaths) async {
    final focusAreas = _args['focus'] as List<String>? ?? [];
    final language = ConfigService.getReportLanguage();

    // Use BatchService for parallel processing with rate limiting
    final results = await _batchService.reviewFilesInBatches(
      filePaths: filePaths,
      focusAreas: focusAreas,
      batchSize: ConfigService.getBatchSize(),
      delayBetweenBatches: Duration(
        milliseconds: ConfigService.getDelayBetweenBatches(),
      ),
      language: language,
    );

    // Store results for report generation
    _reviewResults.addAll(results);
  }

  /// Review a single file
  Future<void> _reviewFile(String filePath) async {
    // ignore: avoid_print
    print('🔍 Reviewing: $filePath');

    try {
      final content = await FileService.readFileContent(filePath);
      if (content == null) {
        // ignore: avoid_print
        print('❌ File not found or could not be read: $filePath');
        _reviewResults.add(
          ReviewResult(
            filePath: filePath,
            fileName: path.basename(filePath),
            review: 'File not found or could not be read',
            timestamp: DateTime.now(),
            hasErrors: true,
            issues: ['File not found or could not be read: $filePath'],
          ),
        );
        return;
      }

      if (content.trim().isEmpty) {
        // ignore: avoid_print
        print('⚠️  File is empty: $filePath');
        _reviewResults.add(
          ReviewResult(
            filePath: filePath,
            fileName: path.basename(filePath),
            review: 'File is empty',
            timestamp: DateTime.now(),
            hasErrors: true,
            issues: ['File is empty'],
          ),
        );
        return;
      }

      final focusAreas = _args['focus'] as List<String>? ?? [];
      final language = ConfigService.getReportLanguage();
      final review = await _apiService.reviewSingleFile(
        code: content,
        filePath: filePath,
        focusAreas: focusAreas,
        language: language,
      );

      _printReview(filePath, review);

      // Parse review results for summary
      final reviewResult = ReviewResult.fromAiResponse(
        filePath: filePath,
        review: review,
      );
      _reviewResults.add(reviewResult);
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error reviewing $filePath: $e');
      _reviewResults.add(
        ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'Error: $e',
          timestamp: DateTime.now(),
          hasErrors: true,
          issues: ['Review error: $e'],
        ),
      );
    }
  }

  /// Print review results
  void _printReview(String filePath, String review) {
    // ignore: avoid_print
    print('📊 Review Results for: ${path.basename(filePath)}');
    // ignore: avoid_print
    print('=' * 60);
    // ignore: avoid_print
    print(review);
    // ignore: avoid_print
    print('=' * 60);
  }

  /// Save language and format settings to config
  Future<void> _saveLanguageAndFormatSettings() async {
    // Only save if explicitly provided in arguments
    if (_args.wasParsed('language')) {
      final language = _args['language'] as String;
      try {
        await ConfigService.setReportLanguage(language);
      } catch (e) {
        // ignore: avoid_print
        print('⚠️  Warning: Could not save language setting: $e');
      }
    }

    if (_args.wasParsed('format')) {
      final format = _args['format'] as String;
      try {
        await ConfigService.setOutputFormat(format);
      } catch (e) {
        // ignore: avoid_print
        print('⚠️  Warning: Could not save format setting: $e');
      }
    }
  }

  /// Run configuration mode
  Future<void> _runConfigMode() async {
    // ignore: avoid_print
    print('⚙️  Code Review Tool Configuration');
    // ignore: avoid_print
    print('');

    // Show current config
    ConfigService.showConfig();

    // ignore: avoid_print
    print('🔧 Configure Settings:');
    // ignore: avoid_print
    print('');

    // Configure language
    final language = await InteractiveService.promptReportLanguage();
    await ConfigService.setReportLanguage(language);

    // Configure format
    final format = await InteractiveService.promptOutputFormat();
    await ConfigService.setOutputFormat(format);

    // Configure batch size
    // ignore: avoid_print
    print('\n📦 Batch Processing:');
    stdout.write(
      'Batch size (1-20, current: ${ConfigService.getBatchSize()}): ',
    );
    final batchSizeInput = stdin.readLineSync()?.trim();
    if (batchSizeInput != null && batchSizeInput.isNotEmpty) {
      final batchSize = int.tryParse(batchSizeInput);
      if (batchSize != null && batchSize >= 1 && batchSize <= 20) {
        await ConfigService.setBatchSize(batchSize);
      }
    }

    // Configure delay
    stdout.write(
      'Delay between batches in ms (0-10000, current: ${ConfigService.getDelayBetweenBatches()}): ',
    );
    final delayInput = stdin.readLineSync()?.trim();
    if (delayInput != null && delayInput.isNotEmpty) {
      final delay = int.tryParse(delayInput);
      if (delay != null && delay >= 0 && delay <= 10000) {
        await ConfigService.setDelayBetweenBatches(delay);
      }
    }

    // Configure other options
    // ignore: avoid_print
    print('\n📊 Report Options:');
    stdout.write('Include timestamps in reports? (Y/n): ');
    final timestampInput = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';
    await ConfigService.setIncludeTimestamps(
      timestampInput == 'y' || timestampInput == 'yes' || timestampInput == '',
    );

    stdout.write('Generate detailed output? (Y/n): ');
    final detailedInput = stdin.readLineSync()?.trim().toLowerCase() ?? 'y';
    await ConfigService.setDetailedOutput(
      detailedInput == 'y' || detailedInput == 'yes' || detailedInput == '',
    );

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('✅ Configuration saved successfully!');
    // ignore: avoid_print
    print('');

    // Show updated config
    ConfigService.showConfig();
  }
}
