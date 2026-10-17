/// The code review tool as a library: every service, model and helper.
///
/// `code_review.dart` is the command-line entry point and imports what it
/// needs from `lib/`. This file is for importers outside the tool's own
/// directory — the tests in `tools/test/` — which cannot name `…/lib/…`
/// with a relative import (`avoid_relative_lib_imports`).
library;

export 'lib/code_review.dart';
