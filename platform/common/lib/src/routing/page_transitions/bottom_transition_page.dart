import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

/// A custom Page that creates a ModalBottomSheetRoute.
///
/// This page is used to display routes as bottom sheets instead of full pages.
/// It supports all the customization options of the standard bottom sheet.
class BottomTransitionPage<T> extends Page<T> {
  /// Creates a BottomTransitionPage.
  ///
  /// The [child] parameter is required and specifies the content of the bottom sheet.
  const BottomTransitionPage({
    required this.child,
    this.backgroundColor,
    this.elevation,
    this.shape,
    this.clipBehavior,
    this.constraints,
    this.transitionAnimationController,
    this.isScrollControlled = false,
    this.useRootNavigator = false,
    this.isDismissible = true,
    this.enableDrag = true,
    this.showDragHandle,
    this.anchorPoint,
    this.barrierColor,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The widget to show in the bottom sheet
  final Widget child;

  /// The background color of the bottom sheet
  final Color? backgroundColor;

  /// The elevation of the bottom sheet
  final double? elevation;

  /// The shape of the bottom sheet
  final ShapeBorder? shape;

  /// How to clip the bottom sheet's content
  final Clip? clipBehavior;

  /// Additional constraints for the bottom sheet
  final BoxConstraints? constraints;

  /// Animation controller for the bottom sheet transition
  final AnimationController? transitionAnimationController;

  /// Whether the bottom sheet can be scrolled to full screen
  final bool isScrollControlled;

  /// Whether to use the root navigator for the bottom sheet
  final bool useRootNavigator;

  /// Whether the bottom sheet can be dismissed by tapping outside
  final bool isDismissible;

  /// Whether the bottom sheet can be dragged
  final bool enableDrag;

  /// Whether to show a drag handle at the top of the bottom sheet
  final bool? showDragHandle;

  /// The anchor point for the bottom sheet
  final Offset? anchorPoint;

  /// The color of the modal barrier behind the bottom sheet
  final Color? barrierColor;

  /// Creates a ModalBottomSheetRoute from this page.
  @override
  Route<T> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<T>(
      settings: this,
      builder: (BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(context.r(16)),
          topRight: Radius.circular(context.r(16)),
        ),
        child: child,
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      transitionAnimationController: transitionAnimationController,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      anchorPoint: anchorPoint,
      modalBarrierColor: barrierColor,
    );
  }
}
