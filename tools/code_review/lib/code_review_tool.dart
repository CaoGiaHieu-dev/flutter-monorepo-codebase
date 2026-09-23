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
      stdout.writeln('Error parsing arguments: $e');
      stdout.writeln(parser.usage);
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

    stdout.writeln('🤖 Starting code review with Gemini AI...');
    stdout.writeln('📁 Working directory: ${Directory.current.path}');
    stdout.writeln('🔑 API Key: ${_apiKey.substring(0, 8)}...');
    if (_args['summary'] as bool) {
      stdout.writeln('📊 Summary will be saved to: $_outputDir/');
    }
    stdout.writeln('');

    // Validate we're in a Flutter project
    if (!await FileAnalyzer.validateFlutterProject()) {
      stdout.writeln('❌ This doesn\'t appear to be a Flutter project.');
      stdout.writeln('💡 Please run this tool from the root of your Flutter project.');
      exit(1);
    }

    // Get files to review based on options
    final filesToReview = await _getFilesToReview();

    if (filesToReview.isEmpty) {
      stdout.writeln('📝 No files found to review.');
      return;
    }

    stdout.writeln('📋 Found ${filesToReview.length} file(s) to review:\n');
    for (final file in filesToReview) {
      stdout.writeln('  • $file');
    }
    stdout.writeln('');

    // Ask user for batch review preference
    final useBatchReview = await _promptBatchReview(filesToReview.length);

    if (useBatchReview) {
      await _reviewFilesBatch(filesToReview);
    } else {
      // Review each file individually
      for (final filePath in filesToReview) {
        await _reviewFile(filePath);
        stdout.writeln(''); // Add spacing between files
      }
    }

    // Generate summary report if enabled
    if (_args['summary'] as bool && _reviewResults.isNotEmpty) {
      await ReportService.generateSummaryReport(
        reviewResults: _reviewResults,
        outputDir: _outputDir,
      );
    }

    stdout.writeln('✅ Code review completed!');
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
    stdout.writeln('🤖 Code Review Tool using Gemini AI\n');
    stdout.writeln('Usage: dart tools/code_review/code_review.dart [options]\n');
    stdout.writeln('Options:');
    stdout.writeln(parser.usage);
    stdout.writeln('\n📚 Examples:');
    stdout.writeln('  # Interactive mode (default - configure all options)');
    stdout.writeln('  dart tools/code_review/code_review.dart\n');
    stdout.writeln('  # Review all Dart files');
    stdout.writeln('  dart tools/code_review/code_review.dart --all\n');
    stdout.writeln('  # Review specific file');
    stdout.writeln('  dart tools/code_review/code_review.dart --file lib/main.dart\n');
    stdout.writeln('  # Review specific folder');
    stdout.writeln(
      '  dart tools/code_review/code_review.dart --folder lib/presentation\n',
    );
    stdout.writeln('  # Review changed files in Git');
    stdout.writeln('  dart tools/code_review/code_review.dart --changed\n');
    stdout.writeln('  # Review staged files');
    stdout.writeln('  dart tools/code_review/code_review.dart --staged\n');
    stdout.writeln('  # Focus on specific aspects');
    stdout.writeln('  dart tools/code_review/code_review.dart --focus security,bugs\n');
    stdout.writeln('  # Exclude generated files');
    stdout.writeln(
      '  dart tools/code_review/code_review.dart --exclude "**/*.g.dart"\n',
    );
    stdout.writeln('  # With API key and custom output');
    stdout.writeln(
      '  dart tools/code_review/code_review.dart --api-key "your_key" --all --output-dir reports\n',
    );
    stdout.writeln('🔑 API Key Setup:');
    stdout.writeln('  1. Environment variable: export GEMINI_API_KEY="your_key"');
    stdout.writeln('  2. Command line: --api-key "your_key"');
    stdout.writeln('  3. Saved key: tools/code_review/.gemini_api_key (gitignored)');
    stdout.writeln('  4. Interactive prompt: Tool will ask if no key is found');
    stdout.writeln('  Get your key at: https://makersuite.google.com/app/apikey');
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

    stdout.writeln('🚀 Review Mode Options:');
    stdout.writeln(
      '1. 🔥 Batch Review (FAST) - Review all $fileCount files concurrently',
    );
    stdout.writeln('2. 📄 Individual Review (DETAILED) - Review each file separately');
    stdout.writeln('');
    stdout.writeln(
      '💡 Batch review processes files in parallel with real-time feedback.',
    );
    stdout.writeln(
      '💡 Individual review is slower but provides more detailed console output.',
    );
    stdout.writeln('');

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
    stdout.writeln('🔍 Reviewing: $filePath');

    try {
      final content = await FileService.readFileContent(filePath);
      if (content == null) {
        stdout.writeln('❌ File not found or could not be read: $filePath');
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
        stdout.writeln('⚠️  File is empty: $filePath');
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
      stdout.writeln('❌ Error reviewing $filePath: $e');
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
    stdout.writeln('📊 Review Results for: ${path.basename(filePath)}');
    stdout.writeln('=' * 60);
    stdout.writeln(review);
    stdout.writeln('=' * 60);
  }

  /// Save language and format settings to config
  Future<void> _saveLanguageAndFormatSettings() async {
    // Only save if explicitly provided in arguments
    if (_args.wasParsed('language')) {
      final language = _args['language'] as String;
      try {
        await ConfigService.setReportLanguage(language);
      } catch (e) {
        stdout.writeln('⚠️  Warning: Could not save language setting: $e');
      }
    }

    if (_args.wasParsed('format')) {
      final format = _args['format'] as String;
      try {
        await ConfigService.setOutputFormat(format);
      } catch (e) {
        stdout.writeln('⚠️  Warning: Could not save format setting: $e');
      }
    }
  }

  /// Run configuration mode
  Future<void> _runConfigMode() async {
    stdout.writeln('⚙️  Code Review Tool Configuration');
    stdout.writeln('');

    // Show current config
    ConfigService.showConfig();

    stdout.writeln('🔧 Configure Settings:');
    stdout.writeln('');

    // Configure language
    final language = await InteractiveService.promptReportLanguage();
    await ConfigService.setReportLanguage(language);

    // Configure format
    final format = await InteractiveService.promptOutputFormat();
    await ConfigService.setOutputFormat(format);

    // Configure batch size
    stdout.writeln('\n📦 Batch Processing:');
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
    stdout.writeln('\n📊 Report Options:');
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

    stdout.writeln('');
    stdout.writeln('✅ Configuration saved successfully!');
    stdout.writeln('');

    // Show updated config
    ConfigService.showConfig();
  }
}
