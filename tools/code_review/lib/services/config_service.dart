import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/constants.dart';

/// Service for managing configuration settings
class ConfigService {
  static String get _configPath => path.join(
    CodeReviewConstants.toolDir,
    CodeReviewConstants.configFileName,
  );

  /// Get current configuration
  static Map<String, dynamic> getConfig() {
    try {
      final configFile = File(_configPath);
      if (!configFile.existsSync()) {
        return _getDefaultConfig();
      }

      final configContent = configFile.readAsStringSync();
      final config = jsonDecode(configContent) as Map<String, dynamic>;

      // Merge with defaults to ensure all keys exist
      final defaultConfig = _getDefaultConfig();
      defaultConfig.addAll(config);

      return defaultConfig;
    } catch (e) {
      stdout.writeln('⚠️  Error reading config: $e');
      return _getDefaultConfig();
    }
  }

  /// Save configuration
  static Future<void> saveConfig(Map<String, dynamic> config) async {
    try {
      final configFile = File(_configPath);

      // Ensure directory exists
      await configFile.parent.create(recursive: true);

      const encoder = JsonEncoder.withIndent('    ');
      await configFile.writeAsString(encoder.convert(config));

      stdout.writeln('✅ Configuration saved successfully!');
    } catch (e) {
      stdout.writeln('❌ Error saving config: $e');
    }
  }

  /// Get report language from config
  static String getReportLanguage() {
    final config = getConfig();
    final language = config['reportLanguage'] as String? ?? 'en';

    // Validate language is supported
    if (CodeReviewConstants.supportedLanguages.contains(language)) {
      return language;
    }

    return 'en'; // Default to English
  }

  /// Set report language
  static Future<void> setReportLanguage(String language) async {
    if (!CodeReviewConstants.supportedLanguages.contains(language)) {
      throw ArgumentError('Unsupported language: $language');
    }

    final config = getConfig();
    config['reportLanguage'] = language;
    await saveConfig(config);
  }

  /// Get output format from config
  static String getOutputFormat() {
    final config = getConfig();
    return config['outputFormat'] as String? ?? 'markdown';
  }

  /// Set output format
  static Future<void> setOutputFormat(String format) async {
    final supportedFormats = ['markdown', 'html', 'json', 'txt'];
    if (!supportedFormats.contains(format)) {
      throw ArgumentError('Unsupported format: $format');
    }

    final config = getConfig();
    config['outputFormat'] = format;
    await saveConfig(config);
  }

  /// Get include timestamps setting
  static bool getIncludeTimestamps() {
    final config = getConfig();
    return config['includeTimestamps'] as bool? ?? true;
  }

  /// Set include timestamps
  static Future<void> setIncludeTimestamps(bool include) async {
    final config = getConfig();
    config['includeTimestamps'] = include;
    await saveConfig(config);
  }

  /// Get detailed output setting
  static bool getDetailedOutput() {
    final config = getConfig();
    return config['detailedOutput'] as bool? ?? true;
  }

  /// Set detailed output
  static Future<void> setDetailedOutput(bool detailed) async {
    final config = getConfig();
    config['detailedOutput'] = detailed;
    await saveConfig(config);
  }

  /// Get default configuration
  static Map<String, dynamic> _getDefaultConfig() {
    return {
      'reportLanguage': 'en',
      'outputFormat': 'markdown',
      'includeTimestamps': true,
      'detailedOutput': true,
      'batchSize': 5,
      'delayBetweenBatches': 2000, // milliseconds
    };
  }

  /// Get batch size from config
  static int getBatchSize() {
    final config = getConfig();
    return config['batchSize'] as int? ?? 5;
  }

  /// Set batch size
  static Future<void> setBatchSize(int size) async {
    if (size < 1 || size > 20) {
      throw ArgumentError('Batch size must be between 1 and 20');
    }

    final config = getConfig();
    config['batchSize'] = size;
    await saveConfig(config);
  }

  /// Get delay between batches (in milliseconds)
  static int getDelayBetweenBatches() {
    final config = getConfig();
    return config['delayBetweenBatches'] as int? ?? 2000;
  }

  /// Set delay between batches
  static Future<void> setDelayBetweenBatches(int delayMs) async {
    if (delayMs < 0 || delayMs > 10000) {
      throw ArgumentError('Delay must be between 0 and 10000 milliseconds');
    }

    final config = getConfig();
    config['delayBetweenBatches'] = delayMs;
    await saveConfig(config);
  }

  /// Show current configuration
  static void showConfig() {
    final config = getConfig();

    stdout.writeln('📋 Current Configuration:');
    stdout.writeln('');
    final languageCode = config['reportLanguage'] as String;
    final languageName =
        CodeReviewConstants.languageNames[languageCode] ?? languageCode;
    stdout.writeln('🌐 Report Language: $languageName ($languageCode)');
    stdout.writeln('📄 Output Format: ${config['outputFormat']}');
    stdout.writeln('⏰ Include Timestamps: ${config['includeTimestamps']}');
    stdout.writeln('📊 Detailed Output: ${config['detailedOutput']}');
    stdout.writeln('📦 Batch Size: ${config['batchSize']}');
    stdout.writeln(
      '⏳ Delay Between Batches: ${config['delayBetweenBatches']}ms',
    );

    if (config.containsKey('geminiApiKey')) {
      final apiKey = config['geminiApiKey'] as String;
      stdout.writeln('🔑 API Key: ${apiKey.substring(0, 8)}...');
    }
    stdout.writeln('');
  }
}
