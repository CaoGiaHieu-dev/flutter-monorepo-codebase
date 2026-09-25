import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

/// A filled, rounded-rectangle button.
///
/// ```dart
/// CustomButton.rectangle(
///   onPressed: submit,
///   child: Text(context.l10nAuth.login),
/// )
/// ```
///
/// Sizes left `null` fall back to the kit's defaults, scaled here — the
/// height from [SharedUiConstants.BUTTON_HEIGHT], the radius from
/// `AppRadius.md`. A size the caller passes is taken as already scaled and
/// used as-is.
class CustomButton extends StatelessWidget {
  const CustomButton.rectangle({
    super.key,
    this.child,
    this.elevation = 0,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderSide = BorderSide.none,
    this.onPressed,
    this.height,
    this.radius,
    this.minWidth = double.infinity,
    this.disable = false,
    this.disableColor,
    this.gradientFillColors,
  });

  /// The radius of the button's corners.
  final double? radius;

  /// The elevation of the button.
  final double elevation;

  /// The height of the button.
  final double? height;

  /// The minimum width of the button; fills the available width by default.
  final double minWidth;

  /// The padding inside the button.
  final EdgeInsetsGeometry padding;

  /// The fill colour; the palette's `primary` by default.
  final Color? color;

  /// The fill colour while disabled; [color] by default.
  final Color? disableColor;

  /// The button's content.
  final Widget? child;

  /// The border of the button.
  final BorderSide borderSide;

  /// Called on tap.
  final VoidCallback? onPressed;

  /// Whether the button is disabled.
  final bool disable;

  /// A gradient fill, drawn instead of [color].
  final List<Color>? gradientFillColors;

  @override
  Widget build(BuildContext context) {
    final radius = this.radius ?? AppRadius.md(context);
    final height = this.height ?? context.h(SharedUiConstants.BUTTON_HEIGHT);
    final gradient = gradientFillColors;
    final backgroundColor = gradient == null
        ? color ?? context.colors.primary
        : null;
    final isTransparent = color == Colors.transparent;
    // A transparent button has no background of its own, so its ripple has to
    // read against whatever is behind it. `textPrimary` inverts with the
    // theme, so the feedback shows in both.
    final feedback = isTransparent
        ? context.colors.textPrimary.withValues(
            alpha: SharedUiConstants.TRANSPARENT_BUTTON_FEEDBACK_ALPHA,
          )
        : null;

    Widget button = MaterialButton(
      minWidth: minWidth,
      height: height,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: borderSide,
      ),
      onPressed: disable ? null : onPressed,
      color: backgroundColor,
      elevation: elevation,
      enableFeedback: false,
      highlightElevation: isTransparent ? 0 : null,
      highlightColor: feedback,
      splashColor: feedback,
      disabledColor: disableColor ?? backgroundColor,
      disabledTextColor: context.colors.primary,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );

    if (gradient != null) {
      button = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: button,
      );
    }

    if (minWidth > 0) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: button,
      );
    }
    return button;
  }
}
