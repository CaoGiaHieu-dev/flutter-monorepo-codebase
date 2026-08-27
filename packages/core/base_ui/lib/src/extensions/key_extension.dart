import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

import '../utils/base_ui_constants.dart';
import 'context_extension.dart';

/// Extension methods for [GlobalKey] to provide additional functionality.
///
/// This extension adds utility methods for working with GlobalKey objects,
/// including getting global paint bounds and showing dropdown menus.
extension GlobalKeyExtension on GlobalKey {
  /// Returns the global paint bounds of the widget associated with this [GlobalKey].
  ///
  /// This method uses the `findRenderObject()` method to get the `RenderObject`
  /// associated with the key. It then uses the `getTransformTo()` method to get
  /// the translation of the `RenderObject` in the global coordinate space.
  /// Finally, it shifts the `paintBounds` of the `RenderObject` by the
  /// translation to get the global paint bounds.
  ///
  /// Returns `null` if the `RenderObject` is not found or its `paintBounds` is null.
  ///
  /// Example:
  /// ```dart
  /// final GlobalKey key = GlobalKey();
  /// final Rect? bounds = key.globalPaintBounds;
  /// if (bounds != null) {
  ///   print('Widget bounds: ${bounds.toString()}');
  /// }
  /// ```
  Rect? get globalPaintBounds {
    final renderObject = currentContext?.findRenderObject();
    final translation = renderObject?.getTransformTo(null).getTranslation();
    if (translation != null && renderObject?.paintBounds != null) {
      final offset = Offset(translation.x, translation.y);
      return renderObject!.paintBounds.shift(offset);
    } else {
      return null;
    }
  }

  /// Shows a dropdown menu at the position of the widget associated with this [GlobalKey].
  ///
  /// This method displays a dropdown menu with the provided [options] list.
  /// The menu is positioned relative to the widget associated with this key.
  ///
  /// Parameters:
  /// - [context]: The build context for showing the menu
  /// - [options]: List of items to display in the dropdown
  /// - [onTap]: Optional callback when an item is selected
  /// - [builder]: Optional custom widget builder for menu items
  /// - [alignment]: Alignment of items within the menu (default: centerLeft)
  /// - [padding]: Padding around menu items
  /// - [elevation]: Elevation of the dropdown menu (default: 0)
  /// - [fixedWidth]: Whether to fix the width to match the key's widget
  /// - [side]: Border side styling for the menu
  /// - [allowEmptySelection]: Whether to allow selecting empty/null values
  /// - [shape]: Custom shape for the dropdown menu
  ///
  /// Returns the selected item of type [T], or null if nothing is selected.
  ///
  /// Example:
  /// ```dart
  /// final GlobalKey dropdownKey = GlobalKey();
  ///
  /// final String? selected = await dropdownKey.showDropDown<String>(
  ///   context,
  ///   options: ['Option 1', 'Option 2', 'Option 3'],
  ///   onTap: (value) => print('Selected: $value'),
  /// );
  /// ```
  Future<T?> showDropDown<T>(
    BuildContext context, {
    required List<T> options,
    ValueChanged<T?>? onTap,
    Widget Function(BuildContext context, T item)? builder,
    Alignment alignment = Alignment.centerLeft,
    EdgeInsets? padding,
    double elevation = 0,
    bool fixedWidth = false,
    BorderSide? side,
    bool allowEmptySelection = false,
    OutlinedBorder? shape,
  }) async {
    if (options.isEmpty) return null;
    // Get the render object of the widget associated with the key
    final button = currentContext?.findRenderObject()! as RenderBox;

    // Get the render object of the overlay
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    // Calculate the position of the dropdown menu relative to the button
    // `localToGlobal` converts local coordinates to global coordinates
    // `ancestor: overlay` specifies the overlay as the ancestor for the global coordinates
    // The `RelativeRect` object is used to position the dropdown menu relative to the overlay
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + Offset.zero,
          ancestor: overlay,
        ),
      ),
      Offset(0, context.h(BaseUiConstants.DROPDOWN_VERTICAL_OFFSET)) &
          overlay.size,
    );

    // Get the size of the screen
    final size = MediaQuery.sizeOf(context);

    // Calculate the maximum height of the dropdown menu
    // The maximum height is 1/3 of the screen height or screen width, whichever is larger
    final realHeight = size.height > size.width ? size.height : size.width;

    // Add an empty item at the top if allowEmptySelection is true
    final modifiedOptions = allowEmptySelection ? [null, ...options] : options;

    // Show the dropdown menu using the `showMenu` method
    // `showMenu` is a custom method that displays a menu with the specified configuration
    return showMenu<T?>(
      context: context,
      elevation: elevation,
      color: context.colors.surface,
      shape:
          shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              context.r(BaseUiConstants.DROPDOWN_BORDER_RADIUS),
            ),
            side:
                side ??
                BorderSide(
                  color: context.colors.surfaceVariant,
                  width: context.r(BaseUiConstants.DROPDOWN_BORDER_WIDTH),
                ),
          ),
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: realHeight / BaseUiConstants.DROPDOWN_MAX_HEIGHT_DIVISOR,
        minWidth: button.size.width,
        maxWidth: fixedWidth ? button.size.width : double.infinity,
      ),
      position: position,

      // Generate a list of items for the dropdown menu
      // For every item in the `modifiedOptions` list, create two items:
      // one for the item itself and one for a divider
      items: List.generate(modifiedOptions.length * 2 - 1, (index) {
        if (index.isOdd) {
          // If the index is odd, create a divider
          return const PopupMenuDivider();
        }
        // If the index is even, create a menu item
        final int itemIndex = index ~/ 2;
        final item = modifiedOptions[itemIndex];
        return PopupMenuItem<T>(
          onTap: () {
            // When the item is tapped, call the `onTap` callback and pass the item value
            onTap?.call(item);
          },
          height: context.h(BaseUiConstants.DROPDOWN_ITEM_HEIGHT),
          padding: padding,
          child: item == null
              ? const SizedBox()
              : builder?.call(context, item) ??
                    // If the `builder` parameter is null, use the default item builder
                    Align(alignment: alignment, child: Text(item.toString())),
        );
      }),
    );
  }
}
