import 'dart:io';

import '../../code_review/code_review_api.dart';

/// A test-only driver for the parts of `tools/code_review` that read the
/// current directory (the workspace roots, `lib/`, git).
///
/// The tests cannot `Directory.current =` inside `dart test` — it is one
/// process-wide value shared with other test files — so they run this as a
/// process in a fixture workspace instead:
///
/// ```text
/// probe validate
/// probe files [--all] [--file F]... [--folder D] [--changed] [--staged]
///             [--exclude P]...
/// ```
///
/// `validate` prints `true` / `false`; `files` prints one reviewed file per
/// line, exactly what `FileService.getFilesToReview` returns.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'validate') {
    stdout.writeln(await FileAnalyzer.validateFlutterProject());
    return;
  }

  var all = false;
  var changed = false;
  var staged = false;
  String? folder;
  final files = <String>[];
  final excludes = <String>[];
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--all':
        all = true;
      case '--changed':
        changed = true;
      case '--staged':
        staged = true;
      case '--file':
        files.add(args[++i]);
      case '--folder':
        folder = args[++i];
      case '--exclude':
        excludes.add(args[++i]);
    }
  }
  final result = await FileService.getFilesToReview(
    reviewAll: all,
    specificFiles: files,
    folderPath: folder,
    reviewChanged: changed,
    reviewStaged: staged,
    excludePatterns: excludes,
  );
  for (final file in result) {
    stdout.writeln(file);
  }
}
