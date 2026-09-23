import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import '../core/constants.dart';

class ApiKeyService {
  /// Helper to get the config file path
  static String get _configPath => path.join(
    CodeReviewConstants.toolDir,
    CodeReviewConstants.configFileName,
  );

  /// Where a saved key goes: a gitignored file next to the tool, never the
  /// tracked `code_review_config.json`.
  static String get _keyFilePath => path.join(
    CodeReviewConstants.toolDir,
    CodeReviewConstants.apiKeyFileName,
  );

  /// Get API key from environment, arguments, config, or prompt user
  static String getApiKey(ArgResults args) {
    // Try from command line argument first
    if (args['api-key'] != null) {
      final key = args['api-key'] as String;
      if (key.isNotEmpty) return key;
    }

    // Try from environment variable
    final envKey = Platform.environment['GEMINI_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      return envKey;
    }

    // Try the saved key file, then the config file
    final savedKey = _getSavedApiKey();
    if (savedKey.isNotEmpty) {
      return savedKey;
    }
    final configKey = _getApiKeyFromConfig();
    if (configKey.isNotEmpty) {
      return configKey;
    }

    // Prompt user for API key
    return _promptForApiKey();
  }

  static String _getSavedApiKey() {
    try {
      final file = File(_keyFilePath);
      return file.existsSync() ? file.readAsStringSync().trim() : '';
    } catch (e) {
      return '';
    }
  }

  /// Get API key from config file
  static String _getApiKeyFromConfig() {
    try {
      final configFile = File(_configPath);
      if (!configFile.existsSync()) {
        return '';
      }

      final configContent = configFile.readAsStringSync();
      final config = jsonDecode(configContent) as Map<String, dynamic>;

      final apiKey = config['geminiApiKey'] as String?;
      return apiKey ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Prompt user for API key and optionally save it
  static String _promptForApiKey() {
    stdout.writeln('🔑 Gemini API key not found!');
    stdout.writeln('');
    stdout.writeln(
      '📋 You can get your API key at: https://makersuite.google.com/app/apikey',
    );
    stdout.writeln('');

    stdout.write('🔐 Please enter your Gemini API key: ');
    final apiKey = stdin.readLineSync()?.trim() ?? '';

    if (apiKey.isEmpty) {
      stdout.writeln('❌ No API key provided. Exiting...');
      exit(1);
    }

    // Validate API key format (basic check)
    if (!_isValidApiKeyFormat(apiKey)) {
      stdout.writeln('⚠️  Warning: The API key format doesn\'t look correct.');
      stdout.write('Continue anyway? (y/N): ');
      final confirm = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
      if (confirm != 'y' && confirm != 'yes') {
        stdout.writeln('❌ Cancelled by user. Exiting...');
        exit(1);
      }
    }

    // Ask if user wants to save the key
    stdout.writeln('');
    stdout.write('💾 Save this API key to config file for future use? (y/N): ');
    final saveKey = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';

    if (saveKey == 'y' || saveKey == 'yes') {
      _saveApiKeyToConfig(apiKey);
    }

    return apiKey;
  }

  /// Basic validation for API key format
  static bool _isValidApiKeyFormat(String apiKey) {
    // Gemini API keys typically start with 'AIza' and are around 39 characters
    return apiKey.startsWith('AIza') && apiKey.length >= 35;
  }

  /// Save API key to the gitignored key file
  static void _saveApiKeyToConfig(String apiKey) {
    try {
      File(_keyFilePath).writeAsStringSync('$apiKey\n');
      stdout.writeln('✅ API key saved to $_keyFilePath (gitignored).');
    } catch (e) {
      stdout.writeln('⚠️  Could not save API key: $e');
      stdout.writeln(
        '💡 Export it instead: export GEMINI_API_KEY=your_api_key_here',
      );
    }
  }
}
