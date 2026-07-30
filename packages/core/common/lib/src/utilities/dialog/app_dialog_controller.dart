import 'dart:async';
import 'dart:collection';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

part 'dialog_interface.dart';

typedef OverlayDialogBuilder = Widget Function(BuildContext context);

// --- Helper class to hold queued dialog requests ---
class _DialogRequest<T> {
  final WidgetBuilder builder;
  final String? identity;
  final bool barrierDismissible;
  final Color? barrierColor;
  final String? barrierLabel;
  final bool useSafeArea;
  final Duration transitionDuration;
  final Curve transitionCurve;
  final Completer<T?> completer;

  _DialogRequest({
    required this.builder,
    this.identity,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.useSafeArea,
    required this.transitionDuration,
    required this.transitionCurve,
    required this.completer,
  });
}

class _DialogSession {
  final String internalId;
  final String? userIdentity;
  final OverlayEntry overlayEntry;
  final Completer<dynamic>
  completer; // Completer for when THIS dialog is dismissed
  final AnimationController animationController;

  _DialogSession({
    required this.internalId,
    this.userIdentity,
    required this.overlayEntry,
    required this.completer,
    required this.animationController,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DialogSession &&
          runtimeType == other.runtimeType &&
          internalId == other.internalId;

  @override
  int get hashCode => internalId.hashCode;
}

class AppDialogController {
  static AppDialogController? _instance;
  static final _uuid = const Uuid();

  static AppDialogController get instance {
    assert(
      _instance != null,
      'AppDialogController not initialized. Ensure it is created in MaterialApp builder.',
    );
    return _instance!;
  }

  final OverlayState _overlayState;
  final CapturedThemes _capturedThemes;

  // --- Queue Implementation ---
  final Queue<_DialogRequest<dynamic>> _dialogQueue = Queue();
  bool _isDialogVisible = false; // Track if a dialog is currently shown
  // --- End Queue Implementation ---

  // Changed to track only the *currently visible* dialog session.
  // The queue handles pending dialogs.
  _DialogSession? _currentDialogSession;

  AppDialogController(BuildContext rootContext)
    : _overlayState = Overlay.of(rootContext),
      _capturedThemes = InheritedTheme.capture(
        from: rootContext,
        to: Overlay.of(rootContext).context,
      ) {
    _instance = this;
    DynamicLogger.log(
      '[AppDialog] Controller Initialized',
      level: LogLevel.INFO,
    );
  }

  /// Shows a dialog using an OverlayEntry, managed by a queue.
  ///
  /// Dialogs are shown sequentially in the order they are requested.
  ///
  /// - [builder]: Function that builds the dialog widget.
  /// - [identity]: An optional unique identifier for the dialog. If provided:
  ///   - If a dialog with the same identity is *currently visible* and [forceReopen] is false,
  ///     the new dialog request will be ignored.
  ///   - If a dialog with the same identity is *currently visible* and [forceReopen] is true,
  ///     the *visible* dialog will be dismissed before the new request is added to the queue.
  ///   - If a dialog with the same identity is already *in the queue* (waiting to be shown),
  ///     the *queued* request will be removed before the new request is added. Its original Future completes with null.
  ///   - This identity can be used with `dismiss` to close the *currently visible* dialog if it matches.
  /// - [forceReopen]: If true, dismisses the *currently visible* dialog if it has the same [identity] before queueing the new one. Defaults to false.
  /// - [barrierDismissible]: Whether the dialog can be dismissed by tapping the barrier. Defaults to false.
  /// - [barrierColor]: Color of the barrier. Defaults to Colors.black54.
  /// - [barrierLabel]: Semantic label for the barrier.
  /// - [useSafeArea]: Whether to wrap the dialog content in a SafeArea. Defaults to true.
  /// - [transitionDuration]: Duration of the show/hide animation. Defaults to 300ms.
  /// - [transitionCurve]: Curve for the show/hide animation. Defaults to Curves.easeOutBack.
  ///
  /// Returns a Future that completes with the result passed to `dismiss` when the dialog (after potentially waiting in the queue) is closed.
  /// Returns `Future.value(null)` immediately if a dialog with the same [identity] is currently visible and [forceReopen] is false.
  /// The Future associated with a *queued* request that gets replaced will also complete with `null`.
  static Future<T?> show<T>({
    required OverlayDialogBuilder builder,
    String? identity,
    bool forceReopen = false,
    bool barrierDismissible = false,
    Color? barrierColor = Colors.black54,
    String? barrierLabel,
    bool useSafeArea = true,
    Duration transitionDuration = const Duration(milliseconds: 200),
    Curve transitionCurve = Curves.fastLinearToSlowEaseIn,
  }) {
    final controller = instance;
    final completer = Completer<T?>();

    // Handle visible dialog conflicts
    if (identity != null &&
        !controller._handleVisibleDialogConflict(identity, forceReopen)) {
      return Future.value(null as T?);
    }

    // Remove duplicate requests from queue
    if (identity != null) {
      controller._removeDuplicateQueuedRequests(identity);
    }

    // Create and queue the new request
    final request = _DialogRequest<T>(
      builder: builder,
      identity: identity,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      transitionDuration: transitionDuration,
      transitionCurve: transitionCurve,
      completer: completer,
    );

    controller._dialogQueue.add(request);
    DynamicLogger.log(
      "[AppDialog] Queued dialog request: '${identity ?? 'anonymous'}'. Queue size: ${controller._dialogQueue.length}",
      level: LogLevel.INFO,
    );

    scheduleMicrotask(controller._processQueue);
    return completer.future;
  }

  /// Handles conflicts with currently visible dialogs.
  /// Returns true if processing should continue, false if request should be ignored.
  bool _handleVisibleDialogConflict(String identity, bool forceReopen) {
    if (!_isDialogVisible) return true;

    final currentSession = _currentDialogSession;
    if (currentSession?.userIdentity != identity) return true;

    if (forceReopen) {
      DynamicLogger.log(
        "[AppDialog] Force reopen requested for VISIBLE dialog with identity '$identity'. Dismissing current.",
        level: LogLevel.INFO,
      );
      _dismissInternal<dynamic>(
        internalId: currentSession!.internalId,
        result: null,
      );
      return true;
    } else {
      DynamicLogger.log(
        "[AppDialog] Dialog with identity '$identity' is already VISIBLE and forceReopen is false. Request ignored.",
        level: LogLevel.INFO,
      );
      return false;
    }
  }

  /// Removes duplicate requests from the queue with the same identity.
  void _removeDuplicateQueuedRequests(String identity) {
    _dialogQueue.removeWhere((queuedRequest) {
      if (queuedRequest.identity == identity) {
        DynamicLogger.log(
          "[AppDialog] Found existing request in QUEUE with identity '$identity'. Removing it and completing its future with null.",
          level: LogLevel.INFO,
        );
        _completeRequestSafely(queuedRequest, null);
        return true;
      }
      return false;
    });
  }

  /// Safely completes a dialog request's completer.
  void _completeRequestSafely(_DialogRequest request, dynamic result) {
    if (!request.completer.isCompleted) {
      try {
        request.completer.complete(result);
      } catch (e, s) {
        DynamicLogger.log(
          "[AppDialog] Error completing future for request '${request.identity}': $e\n$s",
          level: LogLevel.WARNING,
        );
      }
    }
  }

  /// Dismisses the *currently visible* dialog.
  ///
  /// - If [identity] is provided, the *currently visible* dialog will be dismissed
  ///   *only if* its identity matches.
  /// - If [identity] is null, the *currently visible* dialog will be dismissed regardless
  ///   of its identity (if one exists).
  /// - [result]: An optional value to return to the caller who originally called `show`
  ///   for the dismissed dialog.
  ///
  /// Note: This does *not* remove items from the pending queue. It only affects the
  /// dialog currently on screen.
  static void dismiss<T>({String? identity, T? result}) {
    instance._dismissInternal<T>(identity: identity, result: result);
  }

  // --- Queue Processing Method ---
  Future<void> _processQueue() async {
    // Ensure the frame is finished before manipulating the overlay
    await WidgetsBinding.instance.endOfFrame;

    if (_isDialogVisible || _dialogQueue.isEmpty) {
      // Either a dialog is already showing, or the queue is empty. Do nothing.
      return;
    }

    _isDialogVisible = true; // Mark that we are now showing a dialog

    // Dequeue the next request. Cast needed because queue holds dynamic.
    final request = _dialogQueue.removeFirst();
    final logIdentity = request.identity ?? 'anonymous_queued';

    DynamicLogger.log(
      "[AppDialog] Processing queued dialog request: '$logIdentity'. Remaining: ${_dialogQueue.length}",
      level: LogLevel.INFO,
    );

    try {
      // Call the actual display logic. This returns a future that completes
      // when the displayed dialog is dismissed.
      final result = await _displayDialog(
        builder: request.builder,
        identity: request.identity,
        barrierDismissible: request.barrierDismissible,
        barrierColor: request.barrierColor,
        barrierLabel: request.barrierLabel,
        useSafeArea: request.useSafeArea,
        transitionDuration: request.transitionDuration,
        transitionCurve: request.transitionCurve,
      );

      // Dialog was dismissed, complete the original completer from the request
      // Check if the completer hasn't already been completed elsewhere (unlikely but safe).
      if (!request.completer.isCompleted) {
        // We need to cast the result back to the expected type T?
        // This is inherently unsafe if the dismiss provides the wrong type,
        // but it's the best we can do with the dynamic queue.
        try {
          request.completer.complete(result); // Use dynamic cast first
        } catch (e) {
          DynamicLogger.log(
            "[AppDialog] Error completing future for '$logIdentity': Type mismatch. Expected ${request.completer.runtimeType}, got ${result?.runtimeType}. Completing with null. Error: $e",
            level: LogLevel.ERROR,
          );
          request.completer.complete(null); // Fallback to null on type error
        }
      }
    } catch (error, stackTrace) {
      // Catch errors during dialog display or dismissal
      DynamicLogger.log(
        "[AppDialog] Error processing dialog '$logIdentity': $error\n$stackTrace",
        level: LogLevel.ERROR,
      );
      // Ensure the original completer is completed with an error
      if (!request.completer.isCompleted) {
        request.completer.completeError(error, stackTrace);
      }
      // Reset state even on error to potentially allow next dialog
      _isDialogVisible = false;
      _currentDialogSession = null; // Clear session on error
      // Try processing next item after error
      scheduleMicrotask(_processQueue);
    }
    // Note: _cleanupDialog now handles setting _isDialogVisible = false
    // and triggering the next _processQueue call upon successful dismissal.
  }
  // --- End Queue Processing Method ---

  /// Clears all dialogs, both visible and queued.
  /// The currently visible dialog will be dismissed (with animation),
  /// and all queued dialog requests will be cancelled.
  void clearAllDialogs() {
    DynamicLogger.log(
      '[AppDialog] Clearing all dialogs (visible and queued)...',
      level: LogLevel.INFO,
    );

    _clearQueuedDialogs();
    _clearVisibleDialog();
  }

  /// Clears all queued dialog requests and completes their futures.
  void _clearQueuedDialogs() {
    final requestsToCancel = _dialogQueue.toList();
    _dialogQueue.clear();

    for (final request in requestsToCancel) {
      _completeRequestSafely(request, null);
    }

    DynamicLogger.log(
      '[AppDialog] Dialog queue cleared. Size: ${_dialogQueue.length}',
      level: LogLevel.INFO,
    );
  }

  /// Clears the currently visible dialog if one exists.
  void _clearVisibleDialog() {
    if (_currentDialogSession != null) {
      final sessionToClear = _currentDialogSession!;
      DynamicLogger.log(
        "[AppDialog] Requesting dismissal of current dialog '${sessionToClear.userIdentity ?? sessionToClear.internalId}' as part of clearAllDialogs.",
        level: LogLevel.INFO,
      );
      _dismissInternal<dynamic>(
        internalId: sessionToClear.internalId,
        result: null,
      );
    } else {
      _validateDialogVisibilityState();
    }
  }

  /// Validates and corrects the dialog visibility state.
  void _validateDialogVisibilityState() {
    if (_isDialogVisible) {
      DynamicLogger.log(
        '[AppDialog] In clearAllDialogs, _currentDialogSession is null but _isDialogVisible was true. Forcing to false.',
        level: LogLevel.WARNING,
      );
      _isDialogVisible = false;
    }
  }

  /// Disposes the AppDialogController, cleaning up all resources.
  /// This should be called when the controller is no longer needed,
  /// typically when the part of the app that initializes it is disposed.
  void dispose() {
    DynamicLogger.log(
      '[AppDialog] Controller disposing...',
      level: LogLevel.INFO,
    );

    _disposeVisibleDialog();
    _disposeQueuedDialogs();
    _finalizeDispose();
  }

  /// Forcefully disposes the currently visible dialog.
  void _disposeVisibleDialog() {
    if (_currentDialogSession == null) return;

    final sessionToDispose = _currentDialogSession!;
    _currentDialogSession = null;

    _stopDialogAnimation(sessionToDispose);
    _removeOverlayEntry(sessionToDispose);
    _disposeAnimationController(sessionToDispose);
    _completeSessionCompleter(sessionToDispose);

    DynamicLogger.log(
      "[AppDialog] Forcefully cleaned up visible dialog '${sessionToDispose.userIdentity ?? sessionToDispose.internalId}' during dispose.",
      level: LogLevel.INFO,
    );
  }

  /// Stops the dialog animation safely.
  void _stopDialogAnimation(_DialogSession session) {
    session.animationController.stop();
  }

  /// Removes the overlay entry safely.
  void _removeOverlayEntry(_DialogSession session) {
    try {
      if (_overlayState.mounted) {
        session.overlayEntry.remove();
      }
    } catch (e) {
      DynamicLogger.log(
        "[AppDialog] Error removing overlay entry during dispose for '${session.userIdentity ?? session.internalId}': $e. It might have already been removed or overlay is unmounted.",
        level: LogLevel.WARNING,
      );
    }
  }

  /// Disposes the animation controller safely.
  void _disposeAnimationController(_DialogSession session) {
    try {
      session.animationController.dispose();
    } catch (e, s) {
      DynamicLogger.log(
        "[AppDialog] Error disposing animationController for '${session.userIdentity ?? session.internalId}' during main controller dispose: $e\n$s",
        level: LogLevel.WARNING,
      );
    }
  }

  /// Completes the session completer if not already completed.
  void _completeSessionCompleter(_DialogSession session) {
    if (!session.completer.isCompleted) {
      session.completer.complete(null);
    }
  }

  /// Disposes all queued dialog requests.
  void _disposeQueuedDialogs() {
    final requestsToCancel = _dialogQueue.toList();
    _dialogQueue.clear();

    for (final request in requestsToCancel) {
      _completeRequestSafely(request, null);
    }

    DynamicLogger.log(
      '[AppDialog] Dialog queue cleared during dispose. Final queue size: ${_dialogQueue.length}',
      level: LogLevel.INFO,
    );
  }

  /// Finalizes the dispose process.
  void _finalizeDispose() {
    _isDialogVisible = false;
    _instance = null;
    DynamicLogger.log(
      '[AppDialog] Controller disposed and instance set to null.',
      level: LogLevel.INFO,
    );
  }

  // Renamed from _showInternal to avoid confusion with the static show
  // This method now focuses *only* on displaying a single dialog.
  Future<dynamic> _displayDialog({
    required WidgetBuilder builder,
    String? identity,
    bool barrierDismissible = true,
    Color? barrierColor = Colors.black54,
    String? barrierLabel,
    bool useSafeArea = true,
    Duration transitionDuration = const Duration(milliseconds: 300),
    Curve transitionCurve = Curves.easeOutBack,
  }) async {
    // This completer is for the lifecycle of *this specific* dialog instance.
    // It completes when this instance is dismissed via _cleanupDialog.
    final sessionCompleter = Completer<dynamic>();
    final internalId = _uuid.v4();

    late _DialogSession session;

    final animationController = AnimationController(
      duration: transitionDuration,
      vsync: _overlayState,
    );

    final overlayEntry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return _AppDialogOverlayEntry(
          key: ValueKey(internalId),
          internalId: internalId,
          builder: builder,
          capturedThemes: _capturedThemes,
          barrierDismissible: barrierDismissible,
          barrierColor: barrierColor,
          barrierLabel: barrierLabel,
          useSafeArea: useSafeArea,
          transitionCurve: transitionCurve,
          animationController: animationController,
          onDismissRequested: (dismissInternalId, result) {
            // Request dismissal using the specific internalId
            _dismissInternal<dynamic>(
              internalId: dismissInternalId,
              result: result,
            );
          },
        );
      },
    );

    session = _DialogSession(
      internalId: internalId,
      userIdentity: identity,
      overlayEntry: overlayEntry,
      completer: sessionCompleter, // Use the session-specific completer
      animationController: animationController,
    );

    // Store the currently visible session
    assert(
      _currentDialogSession == null,
      'Tried to display a dialog while another is tracked as current.',
    );
    _currentDialogSession = session;
    _overlayState.insert(session.overlayEntry);

    animationController.forward();

    DynamicLogger.log(
      "[AppDialog] Showing dialog: '${identity ?? internalId}' (Internal ID: $internalId)",
      level: LogLevel.INFO,
    );

    // Return the future that completes when this specific dialog is dismissed
    return sessionCompleter.future;
  }

  // Helper to find the *current* session by its internal unique ID.
  _DialogSession? _findCurrentSessionByInternalId(String internalId) {
    if (_currentDialogSession?.internalId == internalId) {
      return _currentDialogSession;
    }
    return null;
  }

  // Dismisses the *currently visible* dialog
  void _dismissInternal<T>({String? identity, String? internalId, T? result}) {
    _DialogSession? sessionToDismiss;

    if (internalId != null) {
      // Dismissing by specific internal ID (usually from barrier tap or internal call)
      sessionToDismiss = _findCurrentSessionByInternalId(internalId);
      if (sessionToDismiss == null) {
        DynamicLogger.log(
          "[AppDialog] Dismiss failed: No *visible* dialog found with internal ID '$internalId'. It might have already been dismissed.",
          level: LogLevel.WARNING,
        );
        return; // Nothing to dismiss
      }
    } else if (identity != null) {
      // Dismissing by user-provided identity - check the *visible* dialog
      if (_currentDialogSession?.userIdentity == identity) {
        sessionToDismiss = _currentDialogSession;
        DynamicLogger.log(
          "[AppDialog] Dismissing visible dialog with identity '$identity'.",
          level: LogLevel.INFO,
        );
      } else {
        DynamicLogger.log(
          "[AppDialog] Dismiss failed: No *visible* dialog found with identity '$identity'. Current dialog identity: '${_currentDialogSession?.userIdentity ?? 'none'}'.",
          level: LogLevel.WARNING,
        );
        return; // Nothing to dismiss
      }
    } else {
      // Dismissing the topmost/current dialog (no identity specified)
      if (_currentDialogSession == null) {
        DynamicLogger.log(
          '[AppDialog] Dismiss called but no dialog is currently visible.',
          level: LogLevel.WARNING,
        );
        return; // Nothing to dismiss
      }
      sessionToDismiss = _currentDialogSession;
      final logIdentity =
          sessionToDismiss?.userIdentity ?? sessionToDismiss?.internalId;
      DynamicLogger.log(
        "[AppDialog] Dismissing current dialog: '$logIdentity'.",
        level: LogLevel.INFO,
      );
    }

    // Should only ever be one session to dismiss now
    if (sessionToDismiss != null) {
      // Check if already dismissing
      if (sessionToDismiss.animationController.isAnimating &&
          sessionToDismiss.animationController.status ==
              AnimationStatus.reverse) {
        DynamicLogger.log(
          "[AppDialog] Dismiss animation already reversing for '${sessionToDismiss.userIdentity ?? sessionToDismiss.internalId}'. Skipping.",
          level: LogLevel.INFO,
        );
        return; // Already dismissing
      }
      if (!sessionToDismiss.animationController.isAnimating &&
          sessionToDismiss.animationController.status ==
              AnimationStatus.dismissed) {
        DynamicLogger.log(
          "[AppDialog] Dismiss animation already completed for '${sessionToDismiss.userIdentity ?? sessionToDismiss.internalId}'. Skipping reverse, proceeding to cleanup.",
          level: LogLevel.INFO,
        );
        // Already dismissed, ensure cleanup runs (might happen in race conditions)
        _cleanupDialog(sessionToDismiss, result);
        return;
      }

      // Start the reverse animation. Cleanup happens upon completion.
      sessionToDismiss.animationController.reverse().whenCompleteOrCancel(() {
        _cleanupDialog(
          sessionToDismiss!,
          result,
        ); // Use ! as it's checked non-null
      });
    }
  }

  void _cleanupDialog<TResult>(_DialogSession session, TResult? result) {
    // Check if this is indeed the session we expect to be cleaning up
    if (_currentDialogSession != session && _currentDialogSession != null) {
      // Check if _currentDialogSession is not null before accessing its properties
      DynamicLogger.log(
        "[AppDialog] Cleanup skipped for dialog '${session.userIdentity ?? session.internalId}': It's not the current session (current is '${_currentDialogSession?.userIdentity ?? _currentDialogSession?.internalId ?? 'none'}'). Might be a race condition or stale call.",
        level: LogLevel.WARNING,
      );
      return;
    }

    final logIdentity = session.userIdentity ?? session.internalId;
    DynamicLogger.log(
      "[AppDialog] Cleaning up dialog: '$logIdentity' (Internal ID: ${session.internalId})",
      level: LogLevel.INFO,
    );

    // Clear the current session *before* removing overlay etc.
    _currentDialogSession = null;

    try {
      // Ensure overlay entry is removed only if it's still part of an active overlay
      if (_overlayState.mounted && session.overlayEntry.mounted) {
        session.overlayEntry.remove();
      }
    } catch (e) {
      DynamicLogger.log(
        "[AppDialog] Error removing overlay entry for '$logIdentity': $e. Might have already been removed or overlay is unmounted.",
        level: LogLevel.WARNING,
      );
    }

    session.animationController.dispose();

    // Complete the session's specific completer (awaited by _processQueue)
    if (!session.completer.isCompleted) {
      session.completer.complete(result);
    } else {
      DynamicLogger.log(
        "[AppDialog] Session completer for '$logIdentity' was already completed.",
        level: LogLevel.INFO,
      );
    }

    // --- Queue Trigger ---
    // Mark that no dialog is visible anymore
    _isDialogVisible = false;
    // Try to process the next item in the queue
    scheduleMicrotask(_processQueue);
    // --- End Queue Trigger ---
  }
}

// --- _AppDialogOverlayEntry Widget ---
// (No changes needed here)
class _AppDialogOverlayEntry extends StatefulWidget {
  final String internalId;
  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;
  final bool barrierDismissible;
  final Color? barrierColor;
  final String? barrierLabel;
  final bool useSafeArea;
  final Curve transitionCurve;
  final AnimationController animationController;
  final Function(String internalId, dynamic result) onDismissRequested;

  const _AppDialogOverlayEntry({
    super.key,
    required this.internalId,
    required this.builder,
    required this.capturedThemes,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.useSafeArea,
    required this.transitionCurve,
    required this.animationController,
    required this.onDismissRequested,
  });

  @override
  _AppDialogOverlayEntryState createState() => _AppDialogOverlayEntryState();
}

class _AppDialogOverlayEntryState extends State<_AppDialogOverlayEntry> {
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scaleAnimation = CurvedAnimation(
      parent: widget.animationController,
      curve: widget.transitionCurve,
    );
    _fadeAnimation = CurvedAnimation(
      parent: widget.animationController,
      curve: Curves.easeIn,
    );
  }

  void _handleBarrierTap() {
    if (widget.barrierDismissible) {
      widget.onDismissRequested(widget.internalId, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget dialogContent = Builder(
      builder: (BuildContext dialogContext) {
        return widget.capturedThemes.wrap(widget.builder(dialogContext));
      },
    );

    if (widget.useSafeArea) {
      dialogContent = SafeArea(child: dialogContent);
    }

    dialogContent = Material(
      type: MaterialType.transparency,
      child: dialogContent,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _handleBarrierTap,
            child: Semantics(
              label:
                  widget.barrierLabel ??
                  MaterialLocalizations.of(context).modalBarrierDismissLabel,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(color: widget.barrierColor ?? Colors.black54),
              ),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(scale: _scaleAnimation, child: dialogContent),
        ),
      ],
    );
  }
}

// --- AppDialogControllerInitializer Widget ---
class AppDialogControllerInitializer extends StatefulWidget {
  final Widget child;

  const AppDialogControllerInitializer({super.key, required this.child});

  @override
  State<AppDialogControllerInitializer> createState() =>
      _AppDialogControllerInitializerState();
}

class _AppDialogControllerInitializerState
    extends State<AppDialogControllerInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.endOfFrame.whenComplete(() {
      // Ensure the widget is still mounted before trying to use context or setState
      if (AppDialogController._instance == null && mounted) {
        try {
          AppDialogController(context);
          DynamicLogger.log(
            '[AppDialog] Controller Initialized via Initializer initState.',
            level: LogLevel.INFO,
          );
        } catch (e, s) {
          DynamicLogger.log(
            '[AppDialog] Error during initialization in Initializer: $e\n$s',
            level: LogLevel.ERROR,
          );
        }
      } else if (AppDialogController._instance != null && mounted) {
        // This case can happen if the Initializer widget itself is rebuilt,
        // but the singleton controller instance somehow persisted (e.g. if dispose wasn't called correctly
        // on a previous Initializer, or if it's a global singleton not strictly tied to this Initializer's lifecycle).
        // For a setup where this Initializer is the sole manager, this might indicate an issue.
        DynamicLogger.log(
          '[AppDialog] Controller already initialized when Initializer initState ran. This might be unexpected.',
          level: LogLevel.WARNING,
        );
      } else if (!mounted) {
        DynamicLogger.log(
          '[AppDialog] Initializer initState: component unmounted before initialization could complete.',
          level: LogLevel.INFO,
        );
      }
    });
  }

  @override
  void dispose() {
    // Only dispose the controller if this initializer instance was likely the one
    // that should be managing its lifecycle. Given it's a static instance,
    // care must be taken if multiple initializers could exist.
    if (AppDialogController._instance != null) {
      DynamicLogger.log(
        '[AppDialog] Initializer disposing. Calling AppDialogController.instance.dispose().',
        level: LogLevel.INFO,
      );
      AppDialogController.instance.dispose();
    } else {
      DynamicLogger.log(
        '[AppDialog] Initializer disposing, but AppDialogController.instance was already null.',
        level: LogLevel.INFO,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The AppDialogController is now initialized in initState after the first frame.
    // Accessing AppDialogController.instance before that (e.g. in a descendant's initState)
    // will result in an assertion error.
    return widget.child;
  }
}
