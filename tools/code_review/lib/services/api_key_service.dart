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

    // Try from config file
    final configKey = _getApiKeyFromConfig();
    if (configKey.isNotEmpty) {
      return configKey;
    }

    // Prompt user for API key
    return _promptForApiKey();
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
    // ignore: avoid_print
    print('🔑 Gemini API key not found!');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(
      '📋 You can get your API key at: https://makersuite.google.com/app/apikey',
    );
    // ignore: avoid_print
    print('');

    stdout.write('🔐 Please enter your Gemini API key: ');
    final apiKey = stdin.readLineSync()?.trim() ?? '';

    if (apiKey.isEmpty) {
      // ignore: avoid_print
      print('❌ No API key provided. Exiting...');
      exit(1);
    }

    // Validate API key format (basic check)
    if (!_isValidApiKeyFormat(apiKey)) {
      // ignore: avoid_print
      print('⚠️  Warning: The API key format doesn\'t look correct.');
      stdout.write('Continue anyway? (y/N): ');
      final confirm = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
      if (confirm != 'y' && confirm != 'yes') {
        // ignore: avoid_print
        print('❌ Cancelled by user. Exiting...');
        exit(1);
      }
    }

    // Ask if user wants to save the key
    // ignore: avoid_print
    print('');
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

  /// Save API key to config file
  static void _saveApiKeyToConfig(String apiKey) {
    try {
      final configFile = File(_configPath);
      Map<String, dynamic> config = {};

      // Read existing config if it exists
      if (configFile.existsSync()) {
        final configContent = configFile.readAsStringSync();
        config = jsonDecode(configContent) as Map<String, dynamic>;
      }

      // Add API key to config
      config['geminiApiKey'] = apiKey;

      // Write updated config
      const encoder = JsonEncoder.withIndent('    ');
      configFile.writeAsStringSync(encoder.convert(config));

      // ignore: avoid_print
      print('✅ API key saved to config file successfully!');
      // ignore: avoid_print
      print('💡 You can remove it later by editing: $_configPath');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  Could not save API key to config: $e');
      // ignore: avoid_print
      print('💡 You can manually add it to $_configPath:');
      // ignore: avoid_print
      print('   "geminiApiKey": "your_api_key_here"');
    }
  }
}
