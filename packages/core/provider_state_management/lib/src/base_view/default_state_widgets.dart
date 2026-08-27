import 'package:flutter/material.dart';

/// Minimal built-in loading fallback.
///
/// core packages must never depend on a feature package — callers that want a themed loading state should
/// pass their own `loadingWidget` builder instead of relying on this default.
class DefaultLoadingWidget extends StatelessWidget {
  const DefaultLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator.adaptive());
  }
}

/// Minimal built-in empty-state fallback.
///
/// core packages must never depend on a feature package — callers that want a themed empty state should
/// pass their own `emptyWidget` builder instead of relying on this default.
class DefaultEmptyWidget extends StatelessWidget {
  const DefaultEmptyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
