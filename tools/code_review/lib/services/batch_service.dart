import 'package:path/path.dart' as path;
import '../models/review_result.dart';
import 'api_service.dart';
import 'file_service.dart';

/// Retry information for a file
class RetryInfo {
  final String filePath;
  final List<String> focusAreas;
  final int currentIndex;
  final int totalFiles;
  final String language;
  final DateTime retryAfter;
  final int attemptCount;

  RetryInfo({
    required this.filePath,
    required this.focusAreas,
    required this.currentIndex,
    required this.totalFiles,
    required this.language,
    required this.retryAfter,
    this.attemptCount = 1,
  });

  RetryInfo copyWith({DateTime? retryAfter, int? attemptCount}) {
    return RetryInfo(
      filePath: filePath,
      focusAreas: focusAreas,
      currentIndex: currentIndex,
      totalFiles: totalFiles,
      language: language,
      retryAfter: retryAfter ?? this.retryAfter,
      attemptCount: attemptCount ?? this.attemptCount,
    );
  }
}

/// Service for handling batch review operations with parallel processing
class BatchService {
  final ApiService _apiService;
  final Map<String, ReviewResult> _reviewResults = {};
  final Map<String, RetryInfo> _retryQueue = {};
  final int _maxRetries = 3;

  BatchService(this._apiService);

  /// Process files in parallel batches with rate limiting
  Future<List<ReviewResult>> reviewFilesInBatches({
    required List<String> filePaths,
    required List<String> focusAreas,
    int batchSize = 5,
    Duration delayBetweenBatches = const Duration(seconds: 2),
    String language = 'en',
  }) async {
    // ignore: avoid_print
    print('🔥 Starting parallel batch review of ${filePaths.length} files...');
    // ignore: avoid_print
    print('📊 Processing files concurrently with rate limiting...\n');

    _reviewResults.clear();
    _retryQueue.clear();

    // Split files into batches
    final batches = _createBatches(filePaths, batchSize);

    // ignore: avoid_print
    print(
      '📦 Processing in ${batches.length} batches of up to $batchSize files each...\n',
    );

    try {
      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        // ignore: avoid_print
        print(
          '🚀 Starting batch ${batchIndex + 1}/${batches.length} with ${batch.length} files...',
        );

        // Process current batch in parallel
        final batchResults = await _processBatch(
          batch: batch,
          focusAreas: focusAreas,
          batchIndex: batchIndex,
          totalBatches: batches.length,
          batchSize: batchSize,
          totalFiles: filePaths.length,
          language: language,
        );

        // Add to results (Map ensures we only keep the latest per file)
        for (final result in batchResults) {
          _reviewResults[result.filePath] = result;
        }

        // final completedInBatch = batchResults.length;
        final totalProcessed = _reviewResults.length;

        // ignore: avoid_print
        print(
          '✅ Batch ${batchIndex + 1}/${batches.length} completed. Overall progress: $totalProcessed/${filePaths.length} files\n',
        );

        // Add delay between batches to respect API rate limits
        if (batchIndex < batches.length - 1) {
          // ignore: avoid_print
          print(
            '⏳ Waiting ${delayBetweenBatches.inSeconds} seconds before next batch...\n',
          );
          await Future.delayed(delayBetweenBatches);
        }
      }

      // Process retry queue if any files need retry
      if (_retryQueue.isNotEmpty) {
        // ignore: avoid_print
        print('\n🔄 Processing retry queue (${_retryQueue.length} files)...');
        await _processRetryQueue();
      }

      final finalResults = _reviewResults.values.toList();
      final errorCount = finalResults.where((r) => r.hasErrors).length;

      // ignore: avoid_print
      print('🎉 Batch review completed!');
      // ignore: avoid_print
      print(
        '📊 Summary: ${finalResults.length - errorCount} successful, $errorCount issues/errors, ${finalResults.length} total',
      );

      return finalResults;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Critical error during batch review: $e');
      return _reviewResults.values.toList();
    }
  }

  /// Process retry queue with exponential backoff
  Future<void> _processRetryQueue() async {
    while (_retryQueue.isNotEmpty) {
      // Get files ready for retry
      final now = DateTime.now();
      final readyFiles = _retryQueue.entries
          .where((entry) => entry.value.retryAfter.isBefore(now))
          .toList();

      if (readyFiles.isEmpty) {
        // Wait for the next file to be ready
        final nextRetry = _retryQueue.values
            .map((info) => info.retryAfter)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final waitDuration = nextRetry.difference(now);

        if (waitDuration.inSeconds > 0) {
          // ignore: avoid_print
          print(
            '⏳ Waiting ${waitDuration.inSeconds} seconds for next retry...',
          );
          await Future.delayed(waitDuration);
        }
        continue;
      }

      // ignore: avoid_print
      print('🔄 Retrying ${readyFiles.length} files...');

      // Process ready files
      for (final entry in readyFiles) {
        final filePath = entry.key;
        final retryInfo = entry.value;

        // Remove from retry queue
        _retryQueue.remove(filePath);

        // Retry the file
        final result = await _reviewSingleFile(
          filePath: retryInfo.filePath,
          focusAreas: retryInfo.focusAreas,
          currentIndex: retryInfo.currentIndex,
          totalFiles: retryInfo.totalFiles,
          language: retryInfo.language,
          isRetry: true,
          attemptCount: retryInfo.attemptCount,
        );

        _reviewResults[filePath] = result;
      }

      // Add small delay between retry batches
      if (_retryQueue.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Create batches from file list
  List<List<String>> _createBatches(List<String> filePaths, int batchSize) {
    final batches = <List<String>>[];

    for (int i = 0; i < filePaths.length; i += batchSize) {
      final end = (i + batchSize < filePaths.length)
          ? i + batchSize
          : filePaths.length;
      batches.add(filePaths.sublist(i, end));
    }

    return batches;
  }

  /// Process a single batch of files in parallel
  Future<List<ReviewResult>> _processBatch({
    required List<String> batch,
    required List<String> focusAreas,
    required int batchIndex,
    required int totalBatches,
    required int batchSize,
    required int totalFiles,
    required String language,
  }) async {
    final futures = <Future<ReviewResult>>[];

    // Create concurrent futures for files in current batch
    for (int i = 0; i < batch.length; i++) {
      final filePath = batch[i];
      final globalIndex = batchIndex * batchSize + i + 1;

      final future = _reviewSingleFile(
        filePath: filePath,
        focusAreas: focusAreas,
        currentIndex: globalIndex,
        totalFiles: totalFiles,
        language: language,
      );

      futures.add(future);
    }

    // Wait for all files in batch to complete and return results
    return Future.wait(futures);
  }

  /// Review a single file and return result
  Future<ReviewResult> _reviewSingleFile({
    required String filePath,
    required List<String> focusAreas,
    required int currentIndex,
    required int totalFiles,
    required String language,
    bool isRetry = false,
    int attemptCount = 1,
  }) async {
    final retryPrefix = isRetry ? '🔄 [Retry $attemptCount] ' : '';
    // ignore: avoid_print
    print(
      '$retryPrefix🔍 [$currentIndex/$totalFiles] Starting review: ${path.basename(filePath)}',
    );

    try {
      final content = await FileService.readFileContent(filePath);
      if (content == null) {
        // ignore: avoid_print
        print(
          '❌ [$currentIndex/$totalFiles] File not found: ${path.basename(filePath)}',
        );
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'File not found or could not be read',
          timestamp: DateTime.now(),
          hasErrors: true,
          issues: ['File not found or could not be read: $filePath'],
        );
      }

      if (content.trim().isEmpty) {
        // ignore: avoid_print
        print(
          '⚠️  [$currentIndex/$totalFiles] File is empty: ${path.basename(filePath)}',
        );
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'File is empty',
          timestamp: DateTime.now(),
          hasErrors: true,
          issues: ['File is empty'],
        );
      }

      final review = await _apiService.reviewSingleFile(
        code: content,
        filePath: filePath,
        focusAreas: focusAreas,
        language: language,
      );

      // Print immediate results with brief summary
      // ignore: avoid_print
      print(
        '📊 [$currentIndex/$totalFiles] ✅ Review completed: ${path.basename(filePath)}',
      );

      // Show brief summary
      final lines = review.split('\n');
      final summaryLines = lines
          .where(
            (line) =>
                line.contains('Overall Score:') ||
                line.contains('Issues Found:') ||
                line.contains('High Priority:'),
          )
          .take(3);

      if (summaryLines.isNotEmpty) {
        // ignore: avoid_print
        print('   📋 ${summaryLines.join(' | ')}');
      }

      // Parse and return result
      return ReviewResult.fromAiResponse(filePath: filePath, review: review);
    } on ApiRateLimitException catch (e) {
      // Handle rate limit - add to retry queue
      if (attemptCount < _maxRetries) {
        final retryAfter = DateTime.now().add(Duration(seconds: e.retryAfter));
        // ignore: avoid_print
        print(
          '⏳ [$currentIndex/$totalFiles] Rate limited: ${path.basename(filePath)} - Retry in ${e.retryAfter}s (Attempt $attemptCount/$_maxRetries)',
        );

        _retryQueue[filePath] = RetryInfo(
          filePath: filePath,
          focusAreas: focusAreas,
          currentIndex: currentIndex,
          totalFiles: totalFiles,
          language: language,
          retryAfter: retryAfter,
          attemptCount: attemptCount + 1,
        );

        // Return placeholder result (will be replaced later if retry succeeds)
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'Queued for retry due to rate limit',
          timestamp: DateTime.now(),
          hasErrors: false, // Don't flag as error yet
          issues: ['Rate limit - queued for retry'],
        );
      } else {
        // Max retries exceeded
        // ignore: avoid_print
        print(
          '❌ [$currentIndex/$totalFiles] Max retries exceeded: ${path.basename(filePath)}',
        );
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'Error: Max retries exceeded due to rate limiting',
          timestamp: DateTime.now(),
          hasErrors: true,
          issues: ['Max retries exceeded: Rate Limit'],
        );
      }
    } on ApiTimeoutException {
      // Handle timeout - add to retry queue with shorter delay
      if (attemptCount < _maxRetries) {
        final retryDelay =
            30 * attemptCount; // Exponential backoff: 30s, 60s, 90s
        final retryAfter = DateTime.now().add(Duration(seconds: retryDelay));
        // ignore: avoid_print
        print(
          '⏱️  [$currentIndex/$totalFiles] Timeout: ${path.basename(filePath)} - Retry in ${retryDelay}s (Attempt $attemptCount/$_maxRetries)',
        );

        _retryQueue[filePath] = RetryInfo(
          filePath: filePath,
          focusAreas: focusAreas,
          currentIndex: currentIndex,
          totalFiles: totalFiles,
          language: language,
          retryAfter: retryAfter,
          attemptCount: attemptCount + 1,
        );

        // Return placeholder result
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'Queued for retry due to timeout',
          timestamp: DateTime.now(),
          hasErrors: false,
          issues: ['Timeout - queued for retry'],
        );
      } else {
        // Max retries exceeded
        // ignore: avoid_print
        print(
          '❌ [$currentIndex/$totalFiles] Max retries exceeded: ${path.basename(filePath)}',
        );
        return ReviewResult(
          filePath: filePath,
          fileName: path.basename(filePath),
          review: 'Error: Max retries exceeded due to timeout',
          timestamp: DateTime.now(),
          hasErrors: true,
          issues: ['Max retries exceeded: Timeout'],
        );
      }
    } catch (e) {
      // Handle other errors - no retry
      // ignore: avoid_print
      print(
        '❌ [\$currentIndex/$totalFiles] Error reviewing ${path.basename(filePath)}: \$e',
      );
      return ReviewResult(
        filePath: filePath,
        fileName: path.basename(filePath),
        review: 'Error: \$e',
        timestamp: DateTime.now(),
        hasErrors: true,
        issues: ['Review error: \$e'],
      );
    }
  }
}
