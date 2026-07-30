import 'dart:io';

/// Utility class for Git operations
class GitHelper {
  /// Get files changed in git (both staged and unstaged)
  static Future<List<String>> getChangedFiles() async {
    try {
      final result = await Process.run('git', ['diff', '--name-only', 'HEAD']);
      if (result.exitCode == 0) {
        return (result.stdout as String)
            .split('\n')
            .where((line) => line.trim().isNotEmpty && line.endsWith('.dart'))
            .toList();
      }
    } catch (e) {
      stderr.writeln('⚠️  Error getting changed files: $e');
    }
    return [];
  }

  /// Get files staged for commit
  static Future<List<String>> getStagedFiles() async {
    try {
      final result = await Process.run('git', [
        'diff',
        '--cached',
        '--name-only',
      ]);
      if (result.exitCode == 0) {
        return (result.stdout as String)
            .split('\n')
            .where((line) => line.trim().isNotEmpty && line.endsWith('.dart'))
            .toList();
      }
    } catch (e) {
      stderr.writeln('⚠️  Error getting staged files: $e');
    }
    return [];
  }

  /// Check if current directory is a git repository
  static Future<bool> isGitRepository() async {
    try {
      final result = await Process.run('git', ['rev-parse', '--git-dir']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
}
