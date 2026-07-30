#!/usr/bin/env dart

import 'lib/code_review_tool.dart';

/// Main entry point for the code review tool
Future<void> main(List<String> arguments) async {
  final tool = CodeReviewTool();
  await tool.run(arguments);
}
