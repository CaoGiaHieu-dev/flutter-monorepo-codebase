import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';

/// Widget displayed when there is no content to show
///
/// This widget shows the app logo in a centered layout when lists or
/// content areas are empty. It can optionally be wrapped in a scrollable
/// view to maintain consistent scroll behavior.
class EmptyWidget extends StatelessWidget {
  const EmptyWidget({
    super.key,
    this.controller,
    this.width = 120,
    this.height = 60,
  });

  /// Optional scroll controller for making the empty state scrollable
  final ScrollController? controller;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = Center(
      child: Assets.icons.logo.svg(
        height: height,
        width: width,
        colorFilter: ColorFilter.mode(
          context.colors.surfaceVariant,
          BlendMode.srcIn,
        ),
      ),
    );

    // Return simple centered widget if no scroll controller provided
    if (controller == null) return child;

    // Return scrollable version with pull-to-refresh support
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      controller: controller,
      slivers: [SliverFillRemaining(child: child)],
    );
  }
}
