import 'package:flutter/widgets.dart';

import '../utils/adaptive_constants.dart';

/// Caps [child] at a readable width and centres it in whatever space is
/// left — for forms and long text, which stretched across an iPad or a
/// desktop window become lines too long to read and fields too wide to
/// scan.
///
/// ```dart
/// AdaptiveContent(
///   padding: context.edgeInsets(horizontal: 16),
///   child: const LoginForm(),
/// )
/// ```
///
/// On a phone the window is narrower than [maxWidth], so this changes
/// nothing but the [padding]; the cap only takes effect once there is room
/// to spare. [child] is given the full capped width — a `TextField` or a
/// card spans the column instead of shrinking to its content.
class AdaptiveContent extends StatelessWidget {
  const AdaptiveContent({
    required this.child,
    this.maxWidth = AdaptiveConstants.CONTENT_MAX_WIDTH,
    this.alignment = Alignment.topCenter,
    this.padding,
    super.key,
  }) : assert(maxWidth > 0, 'maxWidth must be positive.');

  /// The content to cap.
  final Widget child;

  /// The widest [child] may be, in logical pixels — not scaled.
  ///
  /// This is a window-space limit, not a design value. It answers how long
  /// a line may get before it is hard to read — a question the reader's eye
  /// settles, not the artboard. Scaling it with `context.w` would tie the
  /// cap to the window-to-design ratio, and wherever that ratio is allowed
  /// to grow with the window, the cap would grow with the very thing it
  /// exists to stop.
  final double maxWidth;

  /// Where the capped column sits in the space left over. Defaults to the
  /// top centre: a form starts at the top, it does not float mid-screen.
  final AlignmentGeometry alignment;

  /// Space kept between the window edges and the column, outside the cap —
  /// so [maxWidth] is the content's own width. Used as given: scale it at
  /// the call site (`context.edgeInsets(horizontal: 16)`).
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget content = Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // Infinite width resolves to the largest the cap allows: the column
        // is exactly min(available, maxWidth) wide.
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
    if (padding case final padding?) {
      content = Padding(padding: padding, child: content);
    }
    return content;
  }
}
