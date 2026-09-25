import 'dart:async';
import 'dart:collection';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';
import 'loading_overlay_widget.dart';
import 'toast_overlay_widget.dart';

part 'overlay_dialog.dart';

/// The app's one overlay system: queued dialogs, a toast and a loading
/// indicator, shown without a [BuildContext] from anywhere — a network
/// callback, a session listener — above every route.
///
/// Created by [AppOverlayInitializer], which the app shell mounts in
/// `MaterialApp.builder`. Stacking, bottom to top: loading < dialog < toast.
///
/// - **Dialogs** ([showDialog]) are queued: one is visible at a time, the
///   next appears when it closes. An [OverlayDialogWidget] closes itself with
///   [OverlayDialogState.closeDialog]; anything else closes the visible one
///   with [dismissDialog]. A system back dismisses a `barrierDismissible`
///   dialog and is swallowed by any other, so the page behind never pops.
/// - **Toast** ([showToast]) replaces the previous one and removes itself.
/// - **Loading** ([showLoading] / [removeLoadingOverlay]).
class AppOverlay {
  AppOverlay._(BuildContext rootContext)
    : _overlayState = Overlay.of(rootContext),
      _capturedThemes = InheritedTheme.capture(
        from: rootContext,
        to: Overlay.of(rootContext).context,
      );

  static AppOverlay? _instance;

  static AppOverlay get _current {
    assert(
      _instance != null,
      'AppOverlay is not initialized: mount AppOverlayInitializer in '
      'MaterialApp.builder. It is created at the end of the first frame.',
    );
    return _instance!;
  }

  final OverlayState _overlayState;
  final CapturedThemes _capturedThemes;

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  OverlayEntry? _loadingEntry;

  final Queue<_DialogRequest<Object?>> _dialogQueue = Queue();
  _DialogSession? _visibleDialog;
  int _nextDialogId = 0;

  // ---------------------------------------------------------------------------
  // Toast
  // ---------------------------------------------------------------------------

  /// Shows [content] as a toast for [duration], replacing any toast shown.
  static void showToast({
    required String content,
    Duration duration = SharedUiConstants.TOAST_DURATION,
  }) {
    final overlay = _current;
    removeToastOverlay();
    final entry = overlay._toastEntry = OverlayEntry(
      builder: (_) =>
          overlay._capturedThemes.wrap(ToastOverlayWidget(content: content)),
    );
    // On top of everything.
    overlay._overlayState.insert(entry);
    overlay._toastTimer = Timer(duration, removeToastOverlay);
  }

  /// Removes the toast, if one is shown.
  static void removeToastOverlay() {
    final overlay = _instance;
    if (overlay == null) return;
    overlay._toastTimer?.cancel();
    overlay._toastTimer = null;
    overlay._toastEntry?.remove();
    overlay._toastEntry = null;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Shows the loading overlay, below any dialog and toast.
  static void showLoading() {
    final overlay = _current;
    removeLoadingOverlay();
    final entry = overlay._loadingEntry = OverlayEntry(
      builder: (_) =>
          overlay._capturedThemes.wrap(const LoadingOverlayWidget()),
    );
    overlay._overlayState.insert(
      entry,
      below: overlay._visibleDialog?.entry ?? overlay._toastEntry,
    );
  }

  /// Removes the loading overlay, if it is shown.
  static void removeLoadingOverlay() {
    final overlay = _instance;
    if (overlay == null) return;
    overlay._loadingEntry?.remove();
    overlay._loadingEntry = null;
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  /// Queues the dialog [builder] builds; it is shown once every dialog queued
  /// before it has closed.
  ///
  /// Returns a future that completes with the result the dialog is closed
  /// with ([OverlayDialogState.closeDialog], [dismissDialog]) — `null` when
  /// it is dismissed by the barrier or the back, replaced, or cleared.
  ///
  /// [identity] de-duplicates: while a dialog with the same identity is
  /// visible the request is ignored (completing with `null`), unless
  /// [forceReopen] closes the visible one first; a queued request with the
  /// same identity is replaced.
  ///
  /// [barrierColor] defaults to the theme's `colorScheme.scrim` (the
  /// palette's `scrim` token). A dialog that is not [barrierDismissible]
  /// swallows the system back instead of letting it pop the page behind.
  static Future<T?> showDialog<T>({
    required WidgetBuilder builder,
    String? identity,
    bool forceReopen = false,
    bool barrierDismissible = false,
    Color? barrierColor,
    String? barrierLabel,
    bool useSafeArea = true,
    Duration transitionDuration = SharedUiConstants.DIALOG_TRANSITION_DURATION,
    Curve transitionCurve = Curves.fastLinearToSlowEaseIn,
  }) {
    final overlay = _current;

    if (identity != null) {
      final visible = overlay._visibleDialog;
      if (visible != null && visible.identity == identity) {
        if (!forceReopen) return Future.value();
        overlay._dismiss(visible.id, null);
      }
      overlay._dialogQueue.removeWhere((queued) {
        if (queued.identity != identity) return false;
        queued.complete(null);
        return true;
      });
    }

    final request = _DialogRequest<T>(
      builder: builder,
      identity: identity,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      transitionDuration: transitionDuration,
      transitionCurve: transitionCurve,
    );
    overlay._dialogQueue.add(request);
    scheduleMicrotask(overlay._showNext);
    return request.completer.future;
  }

  /// Closes the visible dialog — only when its identity is [identity], if
  /// given — completing its [showDialog] future with [result]. Queued
  /// dialogs are untouched.
  static void dismissDialog<T>({String? identity, T? result}) {
    final overlay = _instance;
    final visible = overlay?._visibleDialog;
    if (overlay == null || visible == null) return;
    if (identity != null && visible.identity != identity) return;
    overlay._dismiss(visible.id, result);
  }

  /// Closes the visible dialog and drops every queued one; their futures
  /// complete with `null`.
  static void clearDialogs() {
    final overlay = _instance;
    if (overlay == null) return;
    for (final request in overlay._dialogQueue) {
      request.complete(null);
    }
    overlay._dialogQueue.clear();
    final visible = overlay._visibleDialog;
    if (visible != null) overlay._dismiss(visible.id, null);
  }

  Future<void> _showNext() async {
    // Let the current frame finish before touching the overlay.
    await WidgetsBinding.instance.endOfFrame;
    if (_instance != this || _visibleDialog != null || _dialogQueue.isEmpty) {
      return;
    }

    final request = _dialogQueue.removeFirst();
    final id = _nextDialogId++;
    final controller = AnimationController(
      duration: request.transitionDuration,
      vsync: _overlayState,
    );
    final entry = OverlayEntry(
      builder: (_) => _DialogOverlayEntry(
        key: ValueKey(id),
        id: id,
        request: request,
        capturedThemes: _capturedThemes,
        animation: controller,
        onBarrierTap: () => _dismiss(id, null),
      ),
    );
    _visibleDialog = _DialogSession(
      id: id,
      identity: request.identity,
      entry: entry,
      animation: controller,
      request: request,
    );
    // Above the loading overlay, below the toast.
    _overlayState.insert(entry, below: _toastEntry);
    unawaited(controller.forward());
  }

  /// Closes dialog [id] if it is the visible one; a stale id is a no-op.
  void _dismiss(int id, Object? result) {
    final session = _visibleDialog;
    if (session == null || session.id != id || session.closing) return;
    session.closing = true;
    session.animation.reverse().whenCompleteOrCancel(() {
      _remove(session);
      session.request.complete(result);
      scheduleMicrotask(_showNext);
    });
  }

  void _remove(_DialogSession session) {
    if (_visibleDialog == session) _visibleDialog = null;
    if (session.entry.mounted) session.entry.remove();
    session.animation.dispose();
  }

  /// A system back while a dialog is visible: dismisses a
  /// `barrierDismissible` one, swallows the back for any other. Returns
  /// whether the back was consumed.
  bool _handleSystemBack() {
    final session = _visibleDialog;
    if (session == null) return false;
    if (session.request.barrierDismissible) _dismiss(session.id, null);
    return true;
  }

  void _dispose() {
    removeToastOverlay();
    removeLoadingOverlay();
    for (final request in _dialogQueue) {
      request.complete(null);
    }
    _dialogQueue.clear();
    final session = _visibleDialog;
    if (session != null) {
      session.animation.stop();
      _remove(session);
      session.request.complete(null);
    }
    if (_instance == this) _instance = null;
  }
}

/// Creates [AppOverlay] over the nearest [Overlay] and routes the system back
/// to its dialogs.
///
/// Mount it in `MaterialApp.builder`, inside an `Overlay.wrap` — above the
/// Router, so its back handler runs before the Router's (observers are asked
/// in registration order). The overlay is created at the end of the first
/// frame; before that [AppOverlay] asserts.
class AppOverlayInitializer extends StatefulWidget {
  const AppOverlayInitializer({super.key, required this.child});

  final Widget child;

  @override
  State<AppOverlayInitializer> createState() => _AppOverlayInitializerState();
}

class _AppOverlayInitializerState extends State<AppOverlayInitializer>
    with WidgetsBindingObserver {
  AppOverlay? _overlay;

  @override
  void initState() {
    super.initState();
    // Registered synchronously, here: see the class comment.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.endOfFrame.whenComplete(() {
      if (!mounted) return;
      if (AppOverlay._instance != null) {
        DynamicLogger.log(
          'A second AppOverlayInitializer replaced the first one.',
          tag: 'AppOverlay',
          level: LogLevel.WARNING,
        );
        AppOverlay._instance!._dispose();
      }
      _overlay = AppOverlay._instance = AppOverlay._(context);
    });
  }

  @override
  Future<bool> didPopRoute() async => _overlay?._handleSystemBack() ?? false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay?._dispose();
    _overlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
