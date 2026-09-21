import 'package:core_base_ui/core_base_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A reusable loading widget that displays a centered circular progress indicator
///
/// This widget provides a consistent loading experience throughout the application.
/// It displays an adaptive circular progress indicator (Material on Android,
/// Cupertino on iOS) centered within a rounded container.
///
/// The widget is designed to be used in various contexts such as:
/// - Full-screen loading states
/// - Loading overlays
/// - Button loading states
/// - Content loading placeholders
///
/// Example usage:
/// ```dart
/// // Basic usage with default styling
/// LoadingWidget()
///
/// // Custom background color
/// LoadingWidget(color: Colors.white.withAlpha(0.9))
///
/// // In a conditional widget
/// isLoading ? LoadingWidget() : ContentWidget()
/// ```
class LoadingWidget extends StatelessWidget {
  /// Creates a loading widget with optional custom background color
  ///
  /// [color] Optional background color for the loading container.
  /// If not provided, uses the theme's surface color.
  const LoadingWidget({
    super.key,
    this.color,
    this.radius = 16,
    this.dimension = 100,
  });

  /// Background color for the loading container
  ///
  /// When null, the widget uses the current theme's surface color
  /// to ensure proper contrast with the progress indicator.
  final Color? color;
  final double radius;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        // Rounded corners for a modern appearance
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          // Use provided color or fallback to theme surface color
          color: color ?? context.surface,
          child: SizedBox.square(
            // Fixed square dimensions for consistent sizing
            dimension: dimension,
            child: const UnconstrainedBox(
              // Adaptive progress indicator that follows platform conventions
              // - Material design on Android
              // - Cupertino design on iOS
              child: CircularProgressIndicator.adaptive(),
            ),
          ),
        ),
      ),
    );
  }
}
