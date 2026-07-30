import 'package:path/path.dart' as path;

/// Review result for a single file
class ReviewResult {
  final String filePath;
  final String fileName;
  final String review;
  final DateTime timestamp;
  final bool hasErrors;
  final List<String> issues;
  final List<String> suggestions;
  final Map<String, int> ratings;

  ReviewResult({
    required this.filePath,
    required this.fileName,
    required this.review,
    required this.timestamp,
    this.hasErrors = false,
    this.issues = const [],
    this.suggestions = const [],
    this.ratings = const {},
  });

  /// Parse AI response into a structured ReviewResult
  static ReviewResult fromAiResponse({
    required String filePath,
    required String review,
  }) {
    final issues = <String>[];
    final suggestions = <String>[];
    final ratings = <String, int>{};

    // Ignore technical review errors
    if (review.startsWith('Error:') ||
        review.contains('ApiRateLimitException') ||
        review.contains('ApiTimeoutException') ||
        review.contains('Max retries exceeded')) {
      return ReviewResult(
        filePath: filePath,
        fileName: path.basename(filePath),
        review: review,
        timestamp: DateTime.now(),
        hasErrors: false,
        issues: [], // Don't count technical errors as code issues
      );
    }

    // Helper to clean titles for summary
    String cleanTitle(String text) {
      return text
          .replaceFirst(RegExp(r'^\d+\.\s*'), '') // Strip "1. "
          .replaceFirst(RegExp(r'^(\*|-|•)\s*'), '') // Strip "* "
          .replaceAll('**', '') // Strip bolding
          .split('\n')
          .first // Only take the first line
          .trim();
    }

    // Extract issues
    final issuesMarkers = [
      '### 🚨 Issues Identified',
      '### 🔍 Issues Found',
      '### Issues',
    ];

    int issuesStartIndex = -1;
    for (final marker in issuesMarkers) {
      issuesStartIndex = review.indexOf(marker);
      if (issuesStartIndex != -1) break;
    }

    if (issuesStartIndex != -1) {
      final endMarkers = [
        '### ✅ Positive Aspects',
        '### ✨ Commendations',
        '### 📈 Quality Matrix',
        '### 📈 Overall Rating',
      ];
      int endOfIssuesIndex = -1;
      for (final marker in endMarkers) {
        endOfIssuesIndex = review.indexOf(marker, issuesStartIndex);
        if (endOfIssuesIndex != -1) break;
      }

      final block = endOfIssuesIndex != -1
          ? review.substring(issuesStartIndex, endOfIssuesIndex).trim()
          : review.substring(issuesStartIndex).trim();

      final lines = block.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith('#') ||
            trimmed.toLowerCase().contains('none found'))
          continue;

        // Main issue items are usually numbered in the prompt's output format
        if (RegExp(r'^\d+\.').hasMatch(trimmed)) {
          issues.add(cleanTitle(trimmed));
        }
      }
    }

    // Extract suggestions
    final suggestionsMarkers = [
      '### 🚀 Improvement Suggestions',
      '### 🚀 Key Improvements',
      '### Suggestions',
    ];

    int suggestionsStartIndex = -1;
    for (final marker in suggestionsMarkers) {
      suggestionsStartIndex = review.indexOf(marker);
      if (suggestionsStartIndex != -1) break;
    }

    if (suggestionsStartIndex != -1) {
      final endMarkers = [
        '### ✅ Positive Aspects',
        '### ✨ Commendations',
        '### 📈 Quality Matrix',
        '### 📈 Overall Rating',
      ];
      int endOfSuggestionsIndex = -1;
      for (final marker in endMarkers) {
        endOfSuggestionsIndex = review.indexOf(marker, suggestionsStartIndex);
        if (endOfSuggestionsIndex != -1) break;
      }

      final block = endOfSuggestionsIndex != -1
          ? review
                .substring(suggestionsStartIndex, endOfSuggestionsIndex)
                .trim()
          : review.substring(suggestionsStartIndex).trim();

      final lines = block.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (RegExp(r'^(\d+\.|\*|-|•)').hasMatch(trimmed)) {
          suggestions.add(cleanTitle(trimmed));
        }
      }
    }

    // Improved hasErrors detection
    bool hasErrors =
        review.contains('🔴') &&
        !review.contains('🔴 Critical Violations\nNone found') &&
        !review.contains(
          '#### 🔴',
        ); // Don't trigger on section header if it has no items

    if (!hasErrors) {
      // Check if any extracted issue title contains "Critical" or "🔴"
      hasErrors = issues.any(
        (i) => i.toLowerCase().contains('critical') || i.contains('🔴'),
      );
    }

    // Extract ratings
    final ratingRegex = RegExp(
      r'\|\s*(?:\|\s*)?[\s*]*([^|*]+?)[\s*]*\|\s*(\d+)/10\s*\|',
      multiLine: true,
    );
    final ratingMatches = ratingRegex.allMatches(review);
    for (final match in ratingMatches) {
      final category = match.group(1)?.trim() ?? '';
      if (category.isNotEmpty &&
          category != 'Category' &&
          category != 'Metric' &&
          category != '---' &&
          !category.startsWith('-')) {
        final score = int.tryParse(match.group(2) ?? '0') ?? 0;
        ratings[category] = score;
      }
    }

    return ReviewResult(
      filePath: filePath,
      fileName: path.basename(filePath),
      review: review,
      timestamp: DateTime.now(),
      hasErrors: hasErrors,
      issues: issues,
      suggestions: suggestions,
      ratings: ratings,
    );
  }
}
