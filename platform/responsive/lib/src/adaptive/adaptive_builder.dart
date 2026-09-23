import 'package:flutter/widgets.dart';

import '../context_extension.dart';
import 'adaptive_context_extension.dart';
import 'window_size_class.dart';

/// Builds a widget for the current [WindowSizeClass].
typedef AdaptiveWidgetBuilder = Widget Function(
  BuildContext context,
  WindowSizeClass windowSizeClass,
);

/// Hands [builder] the current window size class, for layouts that branch
/// in code rather than slot by slot.
///
/// ```dart
/// AdaptiveBuilder(
///   builder: (context, windowSizeClass) => GridView.count(
///     crossAxisCount: windowSizeClass.isAtLeast(WindowSizeClass.expanded)
///         ? 3
///         : 1,
///     children: cards,
///   ),
/// )
/// ```
///
/// The class comes from `context.windowSizeClass`, so no
/// `ResponsiveInit` is required — see [AdaptiveContext].
///
/// Rebuilds whenever the window is resized, not only when the class
/// changes, like every widget that scales. Rebuilding on the class alone
/// would need an `InheritedModel` aspect for it, and the saving is small:
/// while the class holds, [builder] returns the same widget types, so the
/// elements and state below are updated in place, not recreated.
class AdaptiveBuilder extends StatelessWidget {
  const AdaptiveBuilder({required this.builder, super.key});

  /// Called with the current window size class on every build.
  final AdaptiveWidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, context.windowSizeClass);
}

/// Shows one layout per window size class.
///
/// ```dart
/// AdaptiveLayout(
///   compact: (_) => const InboxList(),
///   expanded: (_) => const InboxWithPreview(),
/// )
/// ```
///
/// Only [compact] is required. A class with no builder uses the nearest
/// smaller class that has one — the rule of `context.adaptive` — so above,
/// medium shows the list and large and extraLarge show the preview.
///
/// Slots are builders rather than widgets so that only the layout on
/// screen is ever constructed. Crossing into a class served by another
/// builder usually replaces the subtree, and the state inside it (scroll
/// offsets, text being typed) goes with it: keep that state above this
/// widget — in the route-level controller — when it must survive a
/// rotation or a window resize.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    required this.compact,
    this.medium,
    this.expanded,
    this.large,
    this.extraLarge,
    super.key,
  });

  /// Under the medium breakpoint — and the fallback for every wider class.
  final WidgetBuilder compact;

  /// The medium class; falls back to [compact].
  final WidgetBuilder? medium;

  /// The expanded class; falls back to [medium], then [compact].
  final WidgetBuilder? expanded;

  /// The large class; falls back to [expanded], [medium], [compact].
  final WidgetBuilder? large;

  /// The extraLarge class; falls back through every narrower class.
  final WidgetBuilder? extraLarge;

  @override
  Widget build(BuildContext context) {
    final builder = context.adaptive<WidgetBuilder>(
      compact: compact,
      medium: medium,
      expanded: expanded,
      large: large,
      extraLarge: extraLarge,
    );
    return builder(context);
  }
}
