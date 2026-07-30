part of '../custom_button.dart';

/// Widget for _DropDownButton with custom styles
class _DropDownButton<T> extends StatefulWidget {
  const _DropDownButton({
    super.key,
    required this.displayText,
    required this.items,
    required this.onSelected,
    required this.maxWidth,
    required this.disable,
    required this.textStyle,
    required this.builder,
    this.allowEmptySelection = false,
    // Visual properties for the button itself
    required this.padding,
    required this.color,
    required this.elevation,
    required this.height,
    required this.minWidth,
    required this.buttonRadius,
    required this.borderSide,
    required this.gradientFillColors,
  });

  /// The display text for the drop-down button
  final String displayText;

  /// The list of items for the drop-down button
  final List<T> items;

  /// The callback function when an item is selected
  final ValueChanged<T?>? onSelected;

  /// The maximum width of the drop-down button
  final double maxWidth;

  /// Whether the button is disabled
  final bool disable;

  /// The text style for the drop-down button
  final TextStyle? textStyle;

  /// The builder function for custom drop-down items
  final Widget Function(BuildContext context, T item)? builder;

  /// Whether empty selection is allowed for the drop-down button
  final bool allowEmptySelection;

  // Visual properties for the button itself
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double elevation;
  final double height;
  final double minWidth;
  final double buttonRadius;
  final BorderSide borderSide;
  final List<Color>? gradientFillColors;

  @override
  _DropDownButtonState<T> createState() => _DropDownButtonState<T>();
}

/// State class for _DropDownButton
class _DropDownButtonState<T> extends State<_DropDownButton<T>> {
  final GlobalKey _dropDownKey = GlobalKey();

  /// Method to show the drop-down menu
  void _showDropDown(BuildContext context) {
    _dropDownKey.showDropDown<T>(
      context,
      allowEmptySelection: widget.allowEmptySelection,
      builder: widget.builder,
      options: widget.items,
      onTap: (value) {
        if (value == null && !widget.allowEmptySelection) return;
        widget.onSelected?.call(value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        minWidth: widget.minWidth,
      ),
      child: CustomButton.rectangle(
        // Using .rectangle constructor directly
        key: _dropDownKey,
        disable: widget.disable,
        onPressed: widget.disable
            ? null
            : () {
                _showDropDown(context);
              },
        // Pass visual properties
        color: widget.color ?? Theme.of(context).primaryColor,
        disableColor: widget.color != null
            ? widget.color!.withAlpha(0.5.toOpacity)
            : Theme.of(context).disabledColor,
        padding: widget.padding,
        elevation: widget.elevation,
        height: widget.height,
        // minWidth is handled by ConstrainedBox wrapper for _DropDownButton
        radius: widget.buttonRadius,
        borderSide: widget.borderSide,
        gradientFillColors: widget.gradientFillColors,

        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.displayText,
                maxLines: 1,
                style:
                    widget.textStyle ?? AppTextStyles.bodyMediumStyle(context),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: widget.textStyle?.color),
          ],
        ),
      ),
    );
  }
}
