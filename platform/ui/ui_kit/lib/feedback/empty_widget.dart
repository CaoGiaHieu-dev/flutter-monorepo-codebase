import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

/// Widget displayed when there is no content to show
///
/// This widget shows the app logo in a centered layout when lists or
/// content areas are empty. It can optionally be wrapped in a scrollable
/// view to maintain consistent scroll behavior.
class EmptyWidget extends StatelessWidget {
  const EmptyWidget({
    super.key,
    this.controller,
    this.width,
    this.height,
  });

  /// Optional scroll controller for making the empty state scrollable
  final ScrollController? controller;

  /// Logo width, already scaled by the caller. Defaults to
  /// [SharedUiConstants.EMPTY_WIDGET_WIDTH], scaled with `w`.
  final double? width;

  /// Logo height, already scaled by the caller. Defaults to
  /// [SharedUiConstants.EMPTY_WIDGET_HEIGHT], scaled with `h`.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final child = Center(
      child: Assets.icons.logo.svg(
        height: height ?? context.h(SharedUiConstants.EMPTY_WIDGET_HEIGHT),
        width: width ?? context.w(SharedUiConstants.EMPTY_WIDGET_WIDTH),
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
