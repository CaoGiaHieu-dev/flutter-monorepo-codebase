import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/base_ui_constants.dart';
import 'context_extension.dart';

/// Anchors a popup menu to the widget a [GlobalKey] is attached to.
extension GlobalKeyExtension on GlobalKey {
  /// Shows [options] in a menu anchored below this key's widget and returns
  /// the one picked.
  ///
  /// - [onTap] is called with the pick as well — `null` for the empty row of
  ///   [allowEmptySelection] — and not at all when the menu is dismissed.
  /// - [builder] renders a row; by default the item's `toString()`, aligned
  ///   by [alignment] (start-aligned, so it follows right-to-left locales).
  /// - [fixedWidth] caps the menu at the anchor's width.
  ///
  /// Returns the picked item, or `null` when the menu was dismissed, the
  /// empty row was picked, [options] is empty or the key is not attached to
  /// a laid-out widget.
  ///
  /// ```dart
  /// final key = GlobalKey();
  /// final picked = await key.showDropDown<Locale>(
  ///   context,
  ///   options: AppLocalizations.supportedLocales,
  ///   builder: (context, locale) => Text(locale.languageName(context)),
  /// );
  /// ```
  Future<T?> showDropDown<T extends Object>(
    BuildContext context, {
    required List<T> options,
    ValueChanged<T?>? onTap,
    Widget Function(BuildContext context, T item)? builder,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
    EdgeInsets? padding,
    double elevation = 0,
    bool fixedWidth = false,
    BorderSide? side,
    bool allowEmptySelection = false,
    OutlinedBorder? shape,
  }) async {
    if (options.isEmpty) return null;
    final button = currentContext?.findRenderObject();
    if (button is! RenderBox || !button.hasSize) return null;

    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox) return null;

    // The anchor's bottom edge, in the overlay's coordinates; the menu opens
    // there.
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset(0, context.h(BaseUiConstants.DROPDOWN_VERTICAL_OFFSET)) &
          overlay.size,
    );

    // At most a third of the screen's longest side.
    final size = MediaQuery.sizeOf(context);
    final longestSide = size.longestSide;

    // `null` is the empty row; wrapping every value in `_Choice` keeps it
    // apart from a dismissed menu, which `showMenu` also reports as `null`.
    final choices = <_Choice<T>>[
      if (allowEmptySelection) const _Choice(null),
      for (final option in options) _Choice(option),
    ];

    final picked = await showMenu<_Choice<T>>(
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
        maxHeight: longestSide / BaseUiConstants.DROPDOWN_MAX_HEIGHT_DIVISOR,
        minWidth: button.size.width,
        maxWidth: fixedWidth ? button.size.width : double.infinity,
      ),
      position: position,
      items: [
        for (final (index, choice) in choices.indexed) ...[
          if (index > 0) const PopupMenuDivider(),
          PopupMenuItem<_Choice<T>>(
            value: choice,
            height: context.h(BaseUiConstants.DROPDOWN_ITEM_HEIGHT),
            padding: padding,
            child: switch (choice.value) {
              null => const SizedBox.shrink(),
              final item =>
                builder?.call(context, item) ??
                    Align(alignment: alignment, child: Text(item.toString())),
            },
          ),
        ],
      ],
    );

    if (picked == null) return null;
    onTap?.call(picked.value);
    return picked.value;
  }
}

/// One row of [GlobalKeyExtension.showDropDown]; [value] `null` is the empty
/// row.
class _Choice<T extends Object> {
  const _Choice(this.value);

  final T? value;
}
