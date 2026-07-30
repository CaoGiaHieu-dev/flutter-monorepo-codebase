import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/constants.dart';
import '../models/review_result.dart';
import 'config_service.dart';
import 'file_service.dart';
import 'language_service.dart';

/// Service for generating review reports
class ReportService {
  /// Generate comprehensive summary report
  static Future<void> generateSummaryReport({
    required List<ReviewResult> reviewResults,
    String? outputDir,
  }) async {
    if (reviewResults.isEmpty) return;

    // ignore: avoid_print
    print('📊 Generating comprehensive review report...');

    try {
      final outputDirectory = outputDir ?? CodeReviewConstants.defaultOutputDir;
      await FileService.ensureDirectoryExists(outputDirectory);

      final timestamp = DateTime.now();
      final dateStr =
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${timestamp.hour.toString().padLeft(2, '0')}-${timestamp.minute.toString().padLeft(2, '0')}';

      // Generate single comprehensive report
      final reportPath = path.join(
        outputDirectory,
        'code_review_report_${dateStr}_$timeStr.md',
      );
      await _writeComprehensiveReport(reportPath, reviewResults);

      // ignore: avoid_print
      print('✅ Comprehensive review report saved to: $reportPath');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error generating review report: $e');
    }
  }

  /// Write comprehensive report file with 3 sections
  static Future<void> _writeComprehensiveReport(
    String filePath,
    List<ReviewResult> reviewResults,
  ) async {
    final buffer = StringBuffer();
    final timestamp = DateTime.now();
    final language = ConfigService.getReportLanguage();
    final includeTimestamps = ConfigService.getIncludeTimestamps();

    // Header with localization
    buffer.writeln('# ${LanguageService.getText(language, 'report_title')}');
    buffer.writeln('');

    if (includeTimestamps) {
      buffer.writeln(
        '**${LanguageService.getText(language, 'generated')}:** ${timestamp.toString()}',
      );
    }
    buffer.writeln(
      '**${LanguageService.getText(language, 'project')}:** ${path.basename(Directory.current.path)}',
    );
    buffer.writeln(
      '**${LanguageService.getText(language, 'total_files_reviewed')}:** ${reviewResults.length}',
    );
    buffer.writeln('');
    buffer.writeln('---');
    buffer.writeln('');

    // SECTION 1: SUMMARY
    await _writeSummarySection(buffer, reviewResults, language);

    buffer.writeln('---');
    buffer.writeln('');

    // SECTION 2: DETAILED ANALYSIS
    await _writeDetailSection(buffer, reviewResults, language);

    buffer.writeln('---');
    buffer.writeln('');

    // Final verification section
    buffer.writeln(
      '# ${LanguageService.getText(language, 'final_verification')}',
    );
    buffer.writeln('');
    buffer.writeln('After fixing all issues, run these commands to verify:');
    buffer.writeln('');
    buffer.writeln('```bash');
    buffer.writeln('# Format all code');
    buffer.writeln('dart format .');
    buffer.writeln('');
    buffer.writeln('# Run static analysis (should show 0 errors/warnings)');
    buffer.writeln('flutter analyze --fatal-infos');
    buffer.writeln('');
    buffer.writeln('# Run tests to ensure nothing is broken');
    buffer.writeln('flutter test');
    buffer.writeln('');
    buffer.writeln('# Build the app to verify compilation');
    buffer.writeln('flutter build apk --debug');
    buffer.writeln('```');
    buffer.writeln('');
    buffer.writeln(
      '## ${LanguageService.getText(language, 'additional_resources')}',
    );
    buffer.writeln('');
    buffer.writeln(
      '- [Flutter Best Practices](https://flutter.dev/docs/development/best-practices)',
    );
    buffer.writeln(
      '- [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)',
    );
    buffer.writeln(
      '- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)',
    );
    buffer.writeln(
      '- [Flutter Security](https://flutter.dev/docs/development/security)',
    );
    buffer.writeln('');
    buffer.writeln('---');
    buffer.writeln('*${LanguageService.getText(language, 'generated_by')}*');

    await FileService.writeFile(filePath, buffer.toString());
  }

  /// Write Section 1: Summary
  static Future<void> _writeSummarySection(
    StringBuffer buffer,
    List<ReviewResult> reviewResults,
    String language,
  ) async {
    buffer.writeln('# ${LanguageService.getText(language, 'section_summary')}');
    buffer.writeln('');

    // Overall statistics
    final filesWithIssues = reviewResults
        .where((r) => r.hasErrors || r.issues.isNotEmpty)
        .length;
    final totalIssues = reviewResults.fold<int>(
      0,
      (sum, r) => sum + r.issues.length,
    );
    final criticalFiles = reviewResults.where((r) => r.hasErrors).length;

    buffer.writeln(
      '## ${LanguageService.getText(language, 'overall_results')}',
    );
    buffer.writeln('');
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|--------|-------|');
    buffer.writeln(
      '| **${LanguageService.getText(language, 'total_files')}** | ${reviewResults.length} |',
    );
    buffer.writeln(
      '| **${LanguageService.getText(language, 'files_with_issues')}** | $filesWithIssues |',
    );
    buffer.writeln(
      '| **${LanguageService.getText(language, 'critical_files')}** | $criticalFiles |',
    );
    buffer.writeln(
      '| **${LanguageService.getText(language, 'total_issues')}** | $totalIssues |',
    );
    buffer.writeln(
      '| **${LanguageService.getText(language, 'success_rate')}** | ${(((reviewResults.length - filesWithIssues) / reviewResults.length) * 100).toStringAsFixed(1)}% |',
    );
    buffer.writeln('');

    // Priority breakdown
    final highPriorityFiles = reviewResults
        .where((r) => r.hasErrors || r.issues.length > 3)
        .length;
    final mediumPriorityFiles = reviewResults
        .where(
          (r) => !r.hasErrors && r.issues.isNotEmpty && r.issues.length <= 3,
        )
        .length;
    final cleanFiles = reviewResults.length - filesWithIssues;

    buffer.writeln('## 🚦 Priority Breakdown');
    buffer.writeln('');
    buffer.writeln('| Priority | Count | Description |');
    buffer.writeln('|----------|-------|-------------|');
    buffer.writeln(
      '| 🔴 **High** | $highPriorityFiles | Critical errors or 4+ issues |',
    );
    buffer.writeln(
      '| 🟡 **Medium** | $mediumPriorityFiles | 1-3 issues to fix |',
    );
    buffer.writeln('| 🟢 **Clean** | $cleanFiles | No issues found |');
    buffer.writeln('');

    // Top issues summary
    final allIssues = reviewResults.expand((r) => r.issues).toList();
    final issueFrequency = <String, int>{};

    for (final issue in allIssues) {
      final key = issue.length > 50 ? '${issue.substring(0, 50)}...' : issue;
      issueFrequency[key] = (issueFrequency[key] ?? 0) + 1;
    }

    final sortedIssues = issueFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedIssues.isNotEmpty) {
      buffer.writeln('## 🔍 Most Common Issues');
      buffer.writeln('');
      for (int i = 0; i < sortedIssues.length && i < 5; i++) {
        final entry = sortedIssues[i];
        buffer.writeln(
          '${i + 1}. **${entry.key}** (${entry.value} occurrences)',
        );
      }
      buffer.writeln('');
    }
  }

  /// Write Section 2: Detailed Analysis
  static Future<void> _writeDetailSection(
    StringBuffer buffer,
    List<ReviewResult> reviewResults,
    String language,
  ) async {
    buffer.writeln(
      '# ${LanguageService.getText(language, 'section_detailed')}',
    );
    buffer.writeln('');

    // Sort files by priority (high priority first)
    final sortedResults = List<ReviewResult>.from(reviewResults);
    sortedResults.sort((a, b) {
      // High priority: has errors or many issues
      final aPriority = a.hasErrors
          ? 3
          : (a.issues.length > 3 ? 2 : (a.issues.isNotEmpty ? 1 : 0));
      final bPriority = b.hasErrors
          ? 3
          : (b.issues.length > 3 ? 2 : (b.issues.isNotEmpty ? 1 : 0));
      return bPriority.compareTo(aPriority);
    });

    for (final result in sortedResults) {
      final isTechnicalError =
          result.review.startsWith('Error:') ||
          result.review.contains('Max retries exceeded') ||
          result.review.contains('Queued for retry');

      final priority = isTechnicalError
          ? '⚪ UNKNOWN (Technical Error)'
          : (result.hasErrors
                ? '🔴 HIGH'
                : (result.issues.length > 3
                      ? '🟡 MEDIUM'
                      : (result.issues.isNotEmpty ? '🟡 LOW' : '🟢 CLEAN')));

      buffer.writeln('## 📄 ${result.fileName}');
      buffer.writeln('');
      buffer.writeln(
        '**${LanguageService.getText(language, 'path')}:** `${result.filePath}`  ',
      );
      buffer.writeln(
        '**${LanguageService.getText(language, 'priority')}:** $priority  ',
      );
      buffer.writeln(
        '**${LanguageService.getText(language, 'issues_found')}:** ${result.issues.length}  ',
      );
      buffer.writeln(
        '**${LanguageService.getText(language, 'reviewed')}:** ${result.timestamp.toString().substring(0, 19)}',
      );
      buffer.writeln('');

      if (isTechnicalError) {
        buffer.writeln('### ⚠️ Technical Error');
        buffer.writeln('```');
        buffer.writeln(result.review);
        buffer.writeln('```');
      } else {
        // Output the raw AI review content, but strip the repetitive title header if present
        // AI format starts with "## 📝 Code Review: `filename`"
        final rawReview = result.review;
        final lines = rawReview.split('\n');
        final filteredReview = lines
            .where((line) => !line.trim().startsWith('## 📝 Code Review:'))
            .join('\n')
            .trim();

        buffer.writeln(filteredReview);
      }

      buffer.writeln('');
      buffer.writeln('---');
      buffer.writeln('');
    }
  }

  /// Generate batch review report
  static Future<void> generateBatchReport({
    required String batchReview,
    required List<String> filePaths,
    String? outputDir,
  }) async {
    // ignore: avoid_print
    print('📊 Generating batch review report...');

    try {
      final outputDirectory = outputDir ?? CodeReviewConstants.defaultOutputDir;
      await FileService.ensureDirectoryExists(outputDirectory);

      final timestamp = DateTime.now();
      final dateStr =
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${timestamp.hour.toString().padLeft(2, '0')}-${timestamp.minute.toString().padLeft(2, '0')}';

      final reportPath = path.join(
        outputDirectory,
        'batch_review_report_${dateStr}_$timeStr.md',
      );

      final buffer = StringBuffer();
      buffer.writeln('# 📋 Batch Code Review Report');
      buffer.writeln('');
      buffer.writeln('**Generated:** ${timestamp.toString()}');
      buffer.writeln('**Project:** ${path.basename(Directory.current.path)}');
      buffer.writeln('**Files Reviewed:** ${filePaths.length}');
      buffer.writeln('');
      buffer.writeln('## 📁 Reviewed Files');
      buffer.writeln('');
      for (int i = 0; i < filePaths.length; i++) {
        buffer.writeln('${i + 1}. `${filePaths[i]}`');
      }
      buffer.writeln('');
      buffer.writeln('---');
      buffer.writeln('');
      buffer.writeln(batchReview);
      buffer.writeln('');
      buffer.writeln('---');
      buffer.writeln('*Generated by Code Review Tool - Batch Mode*');

      await FileService.writeFile(reportPath, buffer.toString());

      // ignore: avoid_print
      print('✅ Batch review report saved to: $reportPath');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error generating batch report: $e');
    }
  }
}
