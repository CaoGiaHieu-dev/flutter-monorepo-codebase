import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/shared_ui_constants.dart';
import 'loading_overlay_widget.dart';
import 'toast_overlay_widget.dart';

/// A singleton class to manage application overlays without requiring explicit BuildContext.
///
/// This class provides methods for showing and removing various overlay
/// types, such as toast notifications, dialogs, and loading indicators.
/// It must be initialized using [AppOverlayInitializer] at the root of the application.
class AppOverlay {
  static AppOverlay? _instance;

  /// Returns the singleton instance of [AppOverlay].
  static AppOverlay get instance {
    assert(
      _instance != null,
      'AppOverlay not initialized. Ensure it is created in MaterialApp builder or using AppOverlayInitializer.',
    );
    return _instance!;
  }

  final OverlayState _overlayState;
  final CapturedThemes _capturedThemes;

  // Private variables to track overlay states
  OverlayEntry? _overlayToastEntry;
  OverlayEntry? _overlayDialogEntry;
  OverlayEntry? _overlayLoadingEntry;
  Timer? _timer;

  /// Initializes the [AppOverlay] with the provided [rootContext].
  AppOverlay(BuildContext rootContext)
    : _overlayState = Overlay.of(rootContext),
      _capturedThemes = InheritedTheme.capture(
        from: rootContext,
        to: Overlay.of(rootContext).context,
      ) {
    _instance = this;
  }

  /// Shows a toast overlay with the provided content and duration.
  ///
  /// This method removes any existing toast overlay before displaying the new
  /// one. A timer is set to automatically remove the toast after the specified
  /// duration.
  ///
  /// **Example:**
  /// ```dart
  /// AppOverlay.showToast(
  ///   content: 'This is a toast message',
  ///   duration: const Duration(seconds: 2),
  /// );
  /// ```
  static void showToast({
    required String content,
    Duration duration = SharedUiConstants.TOAST_DURATION,
  }) {
    final controller = instance;
    // Remove any existing toast overlay
    removeToastOverlay();

    // Create and insert a new overlay entry
    controller._overlayToastEntry = OverlayEntry(
      builder: (BuildContext context) {
        return controller._capturedThemes.wrap(
          ToastOverlayWidget(content: content),
        );
      },
    );
    controller._overlayState.insert(
      controller._overlayToastEntry!,
      above: controller._overlayDialogEntry,
    );

    // Set a timer to remove the overlay after the specified duration
    controller._timer = Timer(duration, removeToastOverlay);
  }

  /// Shows a dialog overlay with the provided child widget.
  ///
  /// This method removes any existing dialog overlay before displaying the new
  /// one.
  ///
  /// **Example:**
  /// ```dart
  /// AppOverlay.showDialogOverlay(
  ///   child: AlertDialog(
  ///     title: const Text('Dialog Title'),
  ///     content: const Text('This is a dialog message.'),
  ///     actions: [
  ///       TextButton(
  ///         onPressed: () => AppOverlay.removeDialogOverlay(),
  ///         child: const Text('Close'),
  ///       ),
  ///     ],
  ///   ),
  /// );
  /// ```
  static void showDialogOverlay({required Widget child}) {
    final controller = instance;
    // Remove any existing dialog overlay
    removeDialogOverlay();

    // Create and insert a new overlay entry
    controller._overlayDialogEntry = OverlayEntry(
      builder: (BuildContext context) {
        return controller._capturedThemes.wrap(child);
      },
    );
    controller._overlayState.insert(
      controller._overlayDialogEntry!,
      above: controller._overlayLoadingEntry,
      below: controller._overlayToastEntry,
    );
  }

  /// Shows a loading overlay with a simple loading indicator.
  ///
  /// This method removes any existing loading overlay before displaying the new
  /// one.
  ///
  /// **Example:**
  /// ```dart
  /// AppOverlay.showLoading();
  /// // Perform some asynchronous operation here.
  /// AppOverlay.removeLoadingOverlay();
  /// ```
  static void showLoading() {
    final controller = instance;
    // Remove any existing loading overlay
    removeLoadingOverlay();

    // Create and insert a new overlay entry
    controller._overlayLoadingEntry = OverlayEntry(
      builder: (BuildContext context) {
        return controller._capturedThemes.wrap(const LoadingOverlayWidget());
      },
    );
    controller._overlayState.insert(
      controller._overlayLoadingEntry!,
      below: controller._overlayDialogEntry,
    );
  }

  /// Removes the toast overlay.
  ///
  /// This method also cancels any active timer associated with the toast.
  static void removeToastOverlay() {
    _instance?._overlayToastEntry?.remove();
    _instance?._overlayToastEntry = null;

    _instance?._timer?.cancel();
    _instance?._timer = null;
  }

  /// Removes the dialog overlay.
  static void removeDialogOverlay() {
    _instance?._overlayDialogEntry?.remove();
    _instance?._overlayDialogEntry = null;
  }

  /// Removes the loading overlay.
  static void removeLoadingOverlay() {
    _instance?._overlayLoadingEntry?.remove();
    _instance?._overlayLoadingEntry = null;
  }
}

/// A widget that initializes the [AppOverlay] singleton.
///
/// This widget should be placed near the root of the widget tree,
/// typically within the `builder` of a [MaterialApp].
class AppOverlayInitializer extends StatefulWidget {
  final Widget child;

  const AppOverlayInitializer({super.key, required this.child});

  @override
  State<AppOverlayInitializer> createState() => _AppOverlayInitializerState();
}

class _AppOverlayInitializerState extends State<AppOverlayInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppOverlay(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
