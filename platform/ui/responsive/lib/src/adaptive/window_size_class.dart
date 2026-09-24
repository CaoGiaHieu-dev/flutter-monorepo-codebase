import 'package:flutter/foundation.dart';

import '../utils/responsive_constants.dart';

/// The width class of the current window — not of the device.
///
/// Classified from the window, so an iPad in Split View, a desktop window
/// dragged narrow, or a foldable's cover screen each get the class of the
/// space the app actually has. Values follow the Material 3 window size
/// classes; [ResponsiveBreakpoints] moves the boundaries.
enum WindowSizeClass {
  /// Under 600: phones in portrait, a flip phone, a narrow split pane.
  compact,

  /// 600–839: small tablets and foldables in portrait, a half-screen split.
  medium,

  /// 840–1199: tablets in landscape, an unfolded foldable, small desktops.
  expanded,

  /// 1200–1599: large tablets in landscape, desktop windows.
  large,

  /// 1600 and wider: large desktop windows.
  extraLarge;

  /// Whether this class is [other] or wider.
  bool isAtLeast(WindowSizeClass other) => index >= other.index;

  /// Whether this class is narrower than [other].
  bool isSmallerThan(WindowSizeClass other) => index < other.index;
}

/// The height class of the current window.
///
/// Width decides most layouts; height catches the short windows width
/// cannot see — a phone in landscape, a flip phone half folded into
/// tabletop posture, a short desktop window.
enum WindowHeightClass {
  /// Under 480.
  compact,

  /// 480–899.
  medium,

  /// 900 and taller.
  expanded;

  /// Whether this class is [other] or taller.
  bool isAtLeast(WindowHeightClass other) => index >= other.index;
}

/// Where one window size class ends and the next begins, in logical pixels.
///
/// Defaults to the Material 3 window size classes. Supply a different set to
/// [ResponsiveInit] when a design system draws the lines elsewhere.
@immutable
class ResponsiveBreakpoints {
  const ResponsiveBreakpoints({
    this.medium = ResponsiveConstants.BREAKPOINT_MEDIUM,
    this.expanded = ResponsiveConstants.BREAKPOINT_EXPANDED,
    this.large = ResponsiveConstants.BREAKPOINT_LARGE,
    this.extraLarge = ResponsiveConstants.BREAKPOINT_EXTRA_LARGE,
    this.mediumHeight = ResponsiveConstants.BREAKPOINT_HEIGHT_MEDIUM,
    this.expandedHeight = ResponsiveConstants.BREAKPOINT_HEIGHT_EXPANDED,
  }) : assert(
         0 < medium && medium < expanded && expanded < large,
         'Width breakpoints must be positive and ascending.',
       ),
       assert(large < extraLarge, 'Width breakpoints must be ascending.'),
       assert(
         0 < mediumHeight && mediumHeight < expandedHeight,
         'Height breakpoints must be positive and ascending.',
       );

  /// The Material 3 window size classes — the same values as the default
  /// constructor, named for call sites that want to say so.
  ///
  /// A named constructor rather than a `static const`: arch_check R4 keeps
  /// public constants in `utils/`.
  const ResponsiveBreakpoints.material3() : this();

  /// First width of [WindowSizeClass.medium].
  final double medium;

  /// First width of [WindowSizeClass.expanded].
  final double expanded;

  /// First width of [WindowSizeClass.large].
  final double large;

  /// First width of [WindowSizeClass.extraLarge].
  final double extraLarge;

  /// First height of [WindowHeightClass.medium].
  final double mediumHeight;

  /// First height of [WindowHeightClass.expanded].
  final double expandedHeight;

  /// The width class of a window [width] logical pixels wide.
  WindowSizeClass classify(double width) {
    if (width >= extraLarge) return WindowSizeClass.extraLarge;
    if (width >= large) return WindowSizeClass.large;
    if (width >= expanded) return WindowSizeClass.expanded;
    if (width >= medium) return WindowSizeClass.medium;
    return WindowSizeClass.compact;
  }

  /// The height class of a window [height] logical pixels tall.
  WindowHeightClass classifyHeight(double height) {
    if (height >= expandedHeight) return WindowHeightClass.expanded;
    if (height >= mediumHeight) return WindowHeightClass.medium;
    return WindowHeightClass.compact;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResponsiveBreakpoints &&
          other.medium == medium &&
          other.expanded == expanded &&
          other.large == large &&
          other.extraLarge == extraLarge &&
          other.mediumHeight == mediumHeight &&
          other.expandedHeight == expandedHeight;

  @override
  int get hashCode => Object.hash(
    medium,
    expanded,
    large,
    extraLarge,
    mediumHeight,
    expandedHeight,
  );
}
