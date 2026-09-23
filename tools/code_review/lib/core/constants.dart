import 'dart:io';

import 'package:path/path.dart' as path;

/// Core constants for the code review tool
class CodeReviewConstants {
  static String get toolDir => path.dirname(Platform.script.toFilePath());

  static const String geminiApiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent';

  static const String configFileName = 'code_review_config.json';
  static const String apiKeyFileName = '.gemini_api_key';
  static const String promptFileName = 'review_prompt.md';
  static const String defaultOutputDir = 'code_review_reports';

  static const Duration defaultTimeout = Duration(seconds: 60);
  static const int maxOutputTokens = 8192;
  static const double temperature = 0.1;
  static const int topK = 40;
  static const double topP = 0.95;

  /// Where to get a Gemini API key.
  static const String apiKeyUrl = 'https://aistudio.google.com/app/apikey';

  /// The only report format the tool writes. `--format` accepts it alone,
  /// so CI invocations that pass `--format markdown` keep working.
  static const String reportFormat = 'markdown';

  /// Suffixes of generated Dart files — never worth a review, and most are
  /// gitignored. Always excluded, whatever `--exclude` adds.
  static const List<String> generatedSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.config.dart',
    '.module.dart',
    '.gen.dart',
    '.mocks.dart',
  ];

  /// Path segments whose files are always excluded: generated code
  /// (`lib/src/gen/`, flutter_gen / gen-l10n output) and tests.
  static const List<String> excludedPathSegments = [
    '/gen/',
    '/generated/',
    '/test/',
    '/.dart_tool/',
    '/build/',
  ];

  /// File-name prefixes that are generated per project and gitignored
  /// (`flutterfire configure` writes `firebase_options_<flavor>.dart`).
  static const List<String> generatedFilePrefixes = ['firebase_options'];

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
