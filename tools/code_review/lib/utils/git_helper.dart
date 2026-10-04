import 'dart:async';
import 'dart:io';

/// Utility class for Git operations
class GitHelper {
  /// Get files changed in git (both staged and unstaged)
  static Future<List<String>> getChangedFiles() async {
    try {
      // `--diff-filter=d`: not the deleted files — there is nothing to review.
      final result = await Process.run('git', [
        'diff',
        '--name-only',
        '--diff-filter=d',
        'HEAD',
      ]);
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
        '--diff-filter=d',
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
      // Outside a repository git exits (128) without reading stdin, and the
      // write then fails with a broken pipe — on the `done` future as well as
      // on the write. That is "nothing is ignored", not a crash: `--all`
      // outside a git checkout used to die here.
      unawaited(process.stdin.done.catchError((Object _) {}));
      try {
        process.stdin.writeln(paths.join('\n'));
        await process.stdin.close();
      } on SocketException {
        // git is gone already; its exit code below says why.
      }
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
