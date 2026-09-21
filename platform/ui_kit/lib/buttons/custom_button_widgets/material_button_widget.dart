part of '../custom_button.dart';

/// Widget for MaterialButton with custom styles
class _MaterialButtonWidget extends StatelessWidget {
  const _MaterialButtonWidget({
    required this.style,
    required this.radius,
    required this.elevation,
    required this.height,
    required this.minWidth,
    required this.padding,
    required this.color,
    required this.disableColor,
    required this.child,
    required this.borderSide,
    required this.onPressed,
    required this.disable,
    this.gradientFillColors,
  });

  /// The style of the button (rectangle, circle, outlined)
  final ButtonStyle style;

  /// The radius of the button's corners
  final double radius;

  /// The elevation of the button
  final double elevation;

  /// The height of the button
  final double height;

  /// The minimum width of the button
  final double minWidth;

  /// The padding inside the button
  final EdgeInsetsGeometry padding;

  /// The color of the button
  final Color? color;

  /// The color of the button when disabled
  final Color? disableColor;

  /// The child widget inside the button
  final Widget? child;

  /// The border side of the button
  final BorderSide borderSide;

  /// The callback function when the button is pressed
  final VoidCallback? onPressed;

  /// Whether the button is disabled
  final bool disable;

  /// The gradient colors for the button background fill.
  final List<Color>? gradientFillColors;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = gradientFillColors == null
        ? color ?? Theme.of(context).primaryColor
        : null;
    // Create the MaterialButton with the provided properties
    final button = MaterialButton(
      minWidth: minWidth,
      height: height,
      shape: style == ButtonStyle.circle
          ? CircleBorder(side: borderSide)
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: borderSide,
            ),
      onPressed: disable ? null : onPressed,
      color: backgroundColor,
      elevation: elevation,
      enableFeedback: false,
      highlightElevation: color == Colors.transparent ? 0 : null,
      highlightColor: color == Colors.transparent ? Colors.white70 : null,
      splashColor: color == Colors.transparent ? Colors.white70 : null,
      disabledColor: disableColor ?? backgroundColor,
      disabledTextColor: Theme.of(context).primaryColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );

    // If gradient colors are provided, wrap the button in a DecoratedBox
    if (gradientFillColors != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradientFillColors != null
              ? LinearGradient(colors: gradientFillColors!)
              : null,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: button,
      );
    }

    return button;
  }
}
