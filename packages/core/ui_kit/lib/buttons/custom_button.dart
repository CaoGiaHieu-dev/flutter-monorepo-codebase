import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';

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
    this.height = 48,
    this.radius = 8,
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
    this.height = 48,
    this.radius = 30,
    this.minWidth = 54,
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
    double diameter = 48, // Changed from radius to diameter for clarity
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
    double height = 40,
    double minWidth = 40,
    double buttonRadius = 8,
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
    double maxWidth = 125,
    bool disable = false,
    Widget Function(BuildContext context, S item)? dropDropBuilder,
    TextStyle? textStyle,
    bool allowEmptySelection = false,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    Color? color,
    double elevation = 0,
    double height = 48,
    double minWidth = 0,
    double buttonRadius = 8,
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
    this.height = 0,
    this.radius = 0,
    this.minWidth = 0,
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

  /// The radius of the button's corners
  final double radius;

  /// The elevation of the button
  final double elevation;

  /// The height of the button
  final double height;

  /// The minimum width of the button
  final double minWidth;

  /// The maximum width of the button
  final double maxWidth;

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
  @override
  Widget build(BuildContext context) {
    Widget button;
    switch (widget.style) {
      case ButtonStyle.circle:
      case ButtonStyle.rectangle:
        button = _MaterialButtonWidget(
          style: widget.style,
          radius: widget.radius,
          elevation: widget.elevation,
          height: widget.height,
          minWidth: widget.minWidth,
          padding: widget.padding,
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
          padding: widget.padding,
          color: widget.color,
          elevation: widget.elevation,
          height: widget.height,
          minWidth: widget.minWidth,
          buttonRadius: widget.radius,
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
          maxWidth: widget.maxWidth,
          // Use widget.maxWidth for the ConstrainedBox inside _DropDownButton
          disable: widget.disable,
          textStyle: widget.textStyle,
          allowEmptySelection: widget.allowEmptySelection,
          // Pass through visual properties for the button itself
          padding: widget.padding,
          color: widget.color,
          elevation: widget.elevation,
          height: widget.height,
          minWidth: widget.minWidth,
          buttonRadius: widget.radius,
          borderSide: widget.borderSide,
          gradientFillColors: widget.gradientFillColors,
        );
        break;
      case ButtonStyle.outlined:
        button = Stack(
          children: [
            _MaterialButtonWidget(
              style: widget.style,
              radius: widget.radius,
              elevation: widget.elevation,
              height: widget.height,
              minWidth:
                  widget.minWidth, // minWidth for the material button itself
              padding: widget.padding,
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
                    borderRadius: BorderRadius.circular(widget.radius),
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
        (widget.maxWidth != double.infinity ||
            (widget.style != ButtonStyle.circle && widget.minWidth > 0))) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: widget.maxWidth,
        ),
        child: button,
      );
    }
    return button;
  }
}
