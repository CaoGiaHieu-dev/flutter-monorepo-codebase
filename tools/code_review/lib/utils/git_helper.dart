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

  /// The subset of [paths] that git ignores (`git check-ignore --stdin`).
  ///
  /// Empty outside a git repository or when git is missing — the caller then
  /// reviews everything the other filters let through.
  static Future<Set<String>> ignoredFiles(List<String> paths) async {
    if (paths.isEmpty) return {};
    try {
      final process = await Process.start('git', ['check-ignore', '--stdin']);
      process.stdin.writeln(paths.join('\n'));
      await process.stdin.close();
      final out = await process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      await process.stderr.drain<void>();
      // 0: some ignored, 1: none ignored, 128: not a repository.
      if (await process.exitCode != 0) return {};
      return out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
    } on ProcessException {
      return {};
    }
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
