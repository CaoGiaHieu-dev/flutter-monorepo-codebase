part of '../custom_button.dart';

/// Widget for _OptionsButton with custom styles
class _OptionsButton<T> extends StatefulWidget {
  const _OptionsButton({
    super.key,
    required this.items,
    required this.onSelected,
    required this.disable,
    required this.builder,
    required this.child,
    required this.padding,
    required this.color,
    required this.elevation,
    required this.height,
    required this.minWidth,
    required this.buttonRadius,
    required this.borderSide,
    required this.gradientFillColors,
  }) : assert(
         T == OptionsButtonType || T == Object,
         // Allow dynamic or Object for T if items are not strictly OptionsButtonType,
         // but the factory method CustomButton.options ensures T is OptionsButtonType.
         // If T is strictly OptionsButtonType, this assertion can be more specific.
         '_OptionsButton is primarily intended for OptionsButtonType when used with CustomButton.options factory.',
       );

  /// The list of items for the options button
  final List<T> items;

  /// The callback function when an item is selected
  final ValueChanged<T?>? onSelected;

  /// Whether the button is disabled
  final bool disable;

  /// The builder function for custom drop-down items
  final Widget Function(BuildContext context, T item)? builder;

  // Visual properties for the button itself
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double elevation;
  final double height;
  final double minWidth;
  final double buttonRadius;
  final BorderSide borderSide;
  final List<Color>? gradientFillColors;

  @override
  _OptionsButtonState<T> createState() => _OptionsButtonState<T>();
}

/// State class for _OptionsButton
class _OptionsButtonState<T> extends State<_OptionsButton<T>> {
  final GlobalKey _dropDownKey = GlobalKey();

  /// Method to show the drop-down menu
  void _showDropDown(BuildContext context) {
    _dropDownKey.showDropDown<T>(
      context,
      builder:
          widget.builder ??
          (context, item) {
            // Ensure item is OptionsButtonType before switching
            if (item is OptionsButtonType) {
              final castItem = item;
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(switch (castItem) {
                  OptionsButtonType.edit => context.l10n.edit,
                  OptionsButtonType.duplicate => context.l10n.duplicate,
                  OptionsButtonType.close => context.l10n.close,
                }, maxLines: 1),
              );
            }
            // Fallback for other types, though CustomButton.options ensures OptionsButtonType
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(item.toString()),
            );
          },
      options: widget.items,
      onTap: (value) {
        // No need to check for null here if allowEmptySelection is false for options
        widget.onSelected?.call(value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomButton.rectangle(
      // Using .rectangle constructor directly
      key: _dropDownKey,
      onPressed: widget.disable
          ? null
          : () {
              _showDropDown(context);
            },
      disable: widget.disable,
      padding: widget.padding,
      color: widget.color,
      elevation: widget.elevation,
      height: widget.height,
      minWidth: widget.minWidth,
      radius: widget.buttonRadius,
      borderSide: widget.borderSide,
      gradientFillColors: widget.gradientFillColors,
      // Pass visual properties
      child: widget.child,
    );
  }
}
