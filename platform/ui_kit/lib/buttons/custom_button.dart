import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

part 'custom_button_widgets/dropdown_button_widget.dart';
// Part declarations for widget components
part 'custom_button_widgets/material_button_widget.dart';
part 'custom_button_widgets/options_button_widget.dart';

/// CustomButton is a versatile button widget that supports multiple styles such as rectangle, circle, options, and drop-down.
/// It can be used to create buttons with different shapes, sizes, and functionalities.
///
/// Usage:
/// - To create a rectangle button:
///   ```dart
///   CustomButton.rectangle(
///     onPressed: () {},
///     child: Text('Rectangle Button'),
///   )
///   ```
///
/// - To create a circle button:
///   ```dart
///   CustomButton.circle(
///     onPressed: () {},
///     child: Icon(Icons.add),
///   )
///   ```
///
/// - To create an options button:
///   ```dart
///   CustomButton.options(
///     items: OptionsButtonType.values,
///     onSelected: (value) {
///       // Handle selection
///     },
///   )
///   ```
///
/// - To create a drop-down button:
///   ```dart
///   CustomButton.dropDown(
///     displayText: 'Select Option',
///     items: ['Option 1', 'Option 2'],
///     onSelected: (value) {
///       // Handle selection
///     },
///   )
///   ```

/// Enum to define different button styles
enum ButtonStyle { rectangle, circle, options, dropDown, outlined }

/// Enum to define different types of options buttons
enum OptionsButtonType { edit, duplicate, close }

/// CustomButton is a versatile button widget that supports multiple styles such as rectangle, circle, options, and drop-down.
/// It can be used to create buttons with different shapes, sizes, and functionalities.
class CustomButton<T> extends StatefulWidget {
  /// Constructor for rectangle style button
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
  }) : style = ButtonStyle.rectangle,
       maxWidth = double.infinity,
       displayText = null,
       items = null,
       onSelected = null,
       dropDropBuilder = null,
       allowEmptySelection = false,
       textStyle = null,
       gradientBorderColors = null;

  /// Constructor for outlined style button
  const CustomButton.outlined({
    super.key,
    this.child,
    this.elevation = 0,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderSide = const BorderSide(),
    this.onPressed,
    this.height,
    this.radius,
    this.minWidth,
    this.disable = false,
    this.disableColor,
    this.gradientFillColors,
    this.gradientBorderColors,
  }) : style = ButtonStyle.outlined,
       maxWidth = double.infinity,
       displayText = null,
       items = null,
       onSelected = null,
       dropDropBuilder = null,
       allowEmptySelection = false,
       textStyle = null;

  /// Constructor for circle style button
  const CustomButton.circle({
    super.key,
    this.child,
    this.elevation = 0,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderSide = BorderSide.none,
    this.onPressed,
    double? diameter,
    this.disable = false,
    this.disableColor,
    this.gradientFillColors,
  }) : style = ButtonStyle.circle,
       radius = 0, // Circle border radius is handled by CircleBorder shape
       maxWidth = double.infinity,
       displayText = null,
       textStyle = null,
       items = null,
       onSelected = null,
       allowEmptySelection = false,
       dropDropBuilder = null,
       minWidth = diameter,
       height = diameter,
       gradientBorderColors = null;

  /// Static method to create an options button
  static CustomButton options({
    Key? key,
    List<OptionsButtonType> items = OptionsButtonType.values,
    ValueChanged<OptionsButtonType>? onSelected,
    bool disable = false,
    Widget Function(BuildContext context, OptionsButtonType item)?
    dropDropBuilder,
    Widget? child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    Color? color,
    double elevation = 0,
    double? height,
    double? minWidth,
    double? buttonRadius,
    BorderSide borderSide = BorderSide.none,
    List<Color>? gradientFillColors,
  }) {
    return CustomButton<OptionsButtonType>._(
      key: key,
      style: ButtonStyle.options,
      items: items,
      onSelected: (value) {
        if (value == null) return;
        onSelected?.call(value);
      },
      disable: disable,
      dropDropBuilder: dropDropBuilder,
      padding: padding,
      color: color,
      elevation: elevation,
      height: height,
      minWidth: minWidth,
      radius: buttonRadius,
      borderSide: borderSide,
      gradientFillColors: gradientFillColors,
      child: child ?? const Icon(Icons.more_vert),
    );
  }

  /// Static method to create a drop-down button
  static CustomButton dropDown<S>({
    Key? key,
    required String displayText,
    required List<S> items,
    ValueChanged<S?>? onSelected,
    double? maxWidth,
    bool disable = false,
    Widget Function(BuildContext context, S item)? dropDropBuilder,
    TextStyle? textStyle,
    bool allowEmptySelection = false,
    EdgeInsetsGeometry? padding,
    Color? color,
    double elevation = 0,
    double? height,
    double minWidth = 0,
    double? buttonRadius,
    BorderSide borderSide = BorderSide.none,
    List<Color>? gradientFillColors,
  }) {
    return CustomButton<S>._(
      key: key,
      style: ButtonStyle.dropDown,
      displayText: displayText,
      items: items,
      onSelected: onSelected,
      maxWidth: maxWidth,
      disable: disable,
      dropDropBuilder: dropDropBuilder,
      textStyle: textStyle,
      allowEmptySelection: allowEmptySelection,
      padding: padding,
      color: color,
      elevation: elevation,
      height: height,
      minWidth: minWidth,
      radius: buttonRadius,
      borderSide: borderSide,
      gradientFillColors: gradientFillColors,
    );
  }

  /// Private constructor used by the static methods
  const CustomButton._({
    super.key,
    required this.style,
    this.child,
    this.elevation = 0,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderSide = BorderSide.none,
    this.onPressed,
    this.height,
    this.radius,
    this.minWidth,
    this.disable = false,
    this.disableColor,
    this.items,
    this.onSelected,
    this.displayText,
    this.maxWidth = double.infinity,
    this.dropDropBuilder,
    this.textStyle,
    this.allowEmptySelection = false,
    this.gradientFillColors,
    this.gradientBorderColors,
  });

  /// The style of the button (rectangle, circle, options, drop-down, outlined)
  final ButtonStyle style;

  // Sizes left `null` fall back to this style's default from
  // [SharedUiConstants], scaled in `build`. A size the caller passes is taken
  // as already scaled and used as-is.

  /// The radius of the button's corners
  final double? radius;

  /// The elevation of the button
  final double elevation;

  /// The height of the button
  final double? height;

  /// The minimum width of the button
  final double? minWidth;

  /// The maximum width of the button
  final double? maxWidth;

  /// The padding inside the button
  final EdgeInsetsGeometry? padding;

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

  /// The list of items for options or drop-down buttons
  final List<T>? items;

  /// The callback function when an item is selected
  final ValueChanged<T?>? onSelected;

  /// The display text for drop-down buttons
  final String? displayText;

  /// The builder function for custom drop-down items
  final Widget Function(BuildContext context, T item)? dropDropBuilder;

  /// The text style for drop-down buttons
  final TextStyle? textStyle;

  /// Whether empty selection is allowed for drop-down buttons
  final bool allowEmptySelection;

  /// The gradient colors for the button background fill.
  final List<Color>? gradientFillColors;

  /// The gradient colors for the button border (primarily for outlined style).
  final List<Color>? gradientBorderColors;

  @override
  CustomButtonState<T> createState() => CustomButtonState<T>();
}

/// State class for CustomButton
class CustomButtonState<T> extends State<CustomButton<T>> {
  /// The corner radius, or this style's default scaled with `r`.
  double _radius(BuildContext context) =>
      widget.radius ??
      switch (widget.style) {
        ButtonStyle.circle => 0, // The CircleBorder shape draws the circle.
        ButtonStyle.outlined => context.r(
          SharedUiConstants.OUTLINED_BUTTON_RADIUS,
        ),
        _ => context.r(SharedUiConstants.BUTTON_RADIUS),
      };

  /// The height, or this style's default scaled with `h` — or with `r` for a
  /// circle, whose height and width must stay equal.
  double _height(BuildContext context) =>
      widget.height ??
      switch (widget.style) {
        ButtonStyle.circle => context.r(
          SharedUiConstants.CIRCLE_BUTTON_DIAMETER,
        ),
        ButtonStyle.options => context.h(SharedUiConstants.OPTIONS_BUTTON_SIZE),
        _ => context.h(SharedUiConstants.BUTTON_HEIGHT),
      };

  /// The minimum width, or this style's default scaled with `w` (`r` for a
  /// circle).
  double _minWidth(BuildContext context) =>
      widget.minWidth ??
      switch (widget.style) {
        ButtonStyle.circle => context.r(
          SharedUiConstants.CIRCLE_BUTTON_DIAMETER,
        ),
        ButtonStyle.outlined => context.w(
          SharedUiConstants.OUTLINED_BUTTON_MIN_WIDTH,
        ),
        ButtonStyle.options => context.w(
          SharedUiConstants.OPTIONS_BUTTON_SIZE,
        ),
        _ => 0,
      };

  /// The maximum width; a drop-down defaults to a scaled design width.
  double _maxWidth(BuildContext context) =>
      widget.maxWidth ??
      (widget.style == ButtonStyle.dropDown
          ? context.w(SharedUiConstants.DROPDOWN_BUTTON_MAX_WIDTH)
          : double.infinity);

  /// The padding; a drop-down defaults to a scaled design padding.
  EdgeInsetsGeometry _padding(BuildContext context) =>
      widget.padding ??
      (widget.style == ButtonStyle.dropDown
          ? context.edgeInsets(
              horizontal: SharedUiConstants.DROPDOWN_BUTTON_PADDING_HORIZONTAL,
              vertical: SharedUiConstants.DROPDOWN_BUTTON_PADDING_VERTICAL,
            )
          : EdgeInsets.zero);

  @override
  Widget build(BuildContext context) {
    final radius = _radius(context);
    final height = _height(context);
    final minWidth = _minWidth(context);
    final maxWidth = _maxWidth(context);
    final padding = _padding(context);

    Widget button;
    switch (widget.style) {
      case ButtonStyle.circle:
      case ButtonStyle.rectangle:
        button = _MaterialButtonWidget(
          style: widget.style,
          radius: radius,
          elevation: widget.elevation,
          height: height,
          minWidth: minWidth,
          padding: padding,
          color: widget.color,
          disableColor: widget.disableColor,
          borderSide: widget.borderSide,
          onPressed: widget.onPressed,
          disable: widget.disable,
          gradientFillColors: widget.gradientFillColors,
          child: widget.child,
        );
        break;
      case ButtonStyle.options:
        button = _OptionsButton<T>(
          items: widget.items!,
          onSelected: widget.onSelected,
          disable: widget.disable,
          builder: widget.dropDropBuilder,
          padding: padding,
          color: widget.color,
          elevation: widget.elevation,
          height: height,
          minWidth: minWidth,
          buttonRadius: radius,
          borderSide: widget.borderSide,
          gradientFillColors: widget.gradientFillColors,
          // Pass through visual properties for the button itself
          child: widget.child!,
        );
        break;
      case ButtonStyle.dropDown:
        button = _DropDownButton<T>(
          builder: widget.dropDropBuilder,
          displayText: widget.displayText!,
          items: widget.items!,
          onSelected: widget.onSelected,
          maxWidth: maxWidth,
          // Use maxWidth for the ConstrainedBox inside _DropDownButton
          disable: widget.disable,
          textStyle: widget.textStyle,
          allowEmptySelection: widget.allowEmptySelection,
          // Pass through visual properties for the button itself
          padding: padding,
          color: widget.color,
          elevation: widget.elevation,
          height: height,
          minWidth: minWidth,
          buttonRadius: radius,
          borderSide: widget.borderSide,
          gradientFillColors: widget.gradientFillColors,
        );
        break;
      case ButtonStyle.outlined:
        button = Stack(
          children: [
            _MaterialButtonWidget(
              style: widget.style,
              radius: radius,
              elevation: widget.elevation,
              height: height,
              minWidth: minWidth, // minWidth for the material button itself
              padding: padding,
              color: widget.color,
              disableColor: widget.disableColor,
              borderSide: BorderSide.none,
              // Outlined button's border is drawn by the Positioned.fill DecoratedBox
              onPressed: widget.onPressed,
              disable: widget.disable,
              gradientFillColors: widget.gradientFillColors,
              // Pass fill gradient
              child: widget.child,
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: widget.gradientBorderColors != null
                        ? GradientBoxBorder(
                            gradient: LinearGradient(
                              colors: widget.gradientBorderColors!,
                            ),
                            width: widget.borderSide.width,
                          )
                        : Border.all(
                            color: widget.borderSide == BorderSide.none
                                ? Colors.transparent
                                : widget.borderSide.color,
                            width: widget.borderSide.width,
                          ),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ),
          ],
        );
        break;
    }

    // Apply general constraints like maxWidth here, unless the specific button type handles it internally (e.g. _DropDownButton)
    if (widget.style != ButtonStyle.dropDown &&
        (maxWidth != double.infinity ||
            (widget.style != ButtonStyle.circle && minWidth > 0))) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
        ),
        child: button,
      );
    }
    return button;
  }
}
