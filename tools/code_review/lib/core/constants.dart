import 'dart:io';
import 'package:path/path.dart' as path;

/// Core constants for the code review tool
class CodeReviewConstants {
  static String get toolDir => path.dirname(Platform.script.toFilePath());

  static const String geminiApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent';

  static const String configFileName = 'code_review_config.json';
  static const String promptFileName = 'review_prompt.md';
  static const String defaultOutputDir = 'code_review_reports';

  static const Duration defaultTimeout = Duration(seconds: 60);
  static const int maxOutputTokens = 8192;
  static const double temperature = 0.1;
  static const int topK = 40;
  static const double topP = 0.95;

  // File patterns
  static const List<String> defaultExclusions = [
    '.g.dart',
    '.config.dart',
    '.freezed.dart',
    '.mocks.dart',
    'test/',
  ];

  // Focus areas
  static const List<String> focusAreas = [
    'security',
    'performance',
    'bugs',
    'style',
    'architecture',
    'testing',
  ];

  // Supported languages for reports
  static const List<String> supportedLanguages = [
    'en', // English
    'vi', // Vietnamese
    'ja', // Japanese
    'ko', // Korean
    'zh', // Chinese
    'fr', // French
    'de', // German
    'es', // Spanish
  ];

  static const Map<String, String> languageNames = {
    'en': 'English',
    'vi': 'Tiếng Việt',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
  };
}
