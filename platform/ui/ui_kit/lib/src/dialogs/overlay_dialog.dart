part of 'app_overlay.dart';

/// A dialog shown with [AppOverlay.showDialog] that can close itself.
///
/// One class per dialog, in its own `*_dialog.dart` file (RULE-36).
abstract class OverlayDialogWidget extends StatefulWidget {
  const OverlayDialogWidget({super.key});

  @override
  OverlayDialogState<OverlayDialogWidget> createState();
}

/// State of an [OverlayDialogWidget]; [closeDialog] closes exactly this
/// dialog.
abstract class OverlayDialogState<T extends OverlayDialogWidget>
    extends State<T> {
  /// The id of the dialog this state is built in, read once from
  /// [_DialogScope]; `null` when built outside [AppOverlay.showDialog].
  int? _dialogId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dialogId ??= _DialogScope.maybeOf(context)?.id;
  }

  /// Closes this dialog and completes its [AppOverlay.showDialog] future
  /// with [result].
  ///
  /// Only this dialog: once it is gone — dismissed by the barrier, the back
  /// or another caller — a late call is a no-op and never closes the dialog
  /// shown after it. A widget built outside [AppOverlay.showDialog] has no
  /// id and closes whichever dialog is visible.
  void closeDialog([Object? result]) {
    final overlay = AppOverlay._instance;
    if (overlay == null) return;
    final id = _dialogId ?? overlay._visibleDialog?.id;
    if (id != null) overlay._dismiss(id, result);
  }
}

/// A queued [AppOverlay.showDialog] call.
class _DialogRequest<T> {
  _DialogRequest({
    required this.builder,
    required this.identity,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.barrierLabel,
    required this.useSafeArea,
    required this.transitionDuration,
    required this.transitionCurve,
  });

  final WidgetBuilder builder;
  final String? identity;
  final bool barrierDismissible;
  final Color? barrierColor;
  final String? barrierLabel;
  final bool useSafeArea;
  final Duration transitionDuration;
  final Curve transitionCurve;
  final Completer<T?> completer = Completer<T?>();

  /// Completes the caller's future once. A [result] of the wrong type — a
  /// `closeDialog('x')` on a `showDialog<int>` — completes with `null` and is
  /// logged, rather than throwing inside the overlay.
  void complete(Object? result) {
    if (completer.isCompleted) return;
    if (result is T?) {
      completer.complete(result);
      return;
    }
    DynamicLogger.log(
      'Dialog "${identity ?? 'anonymous'}" closed with a '
      '${result.runtimeType}, expected $T; completing with null.',
      tag: 'AppOverlay',
      level: LogLevel.WARNING,
    );
    completer.complete(null);
  }
}

/// The dialog on screen.
class _DialogSession {
  _DialogSession({
    required this.id,
    required this.identity,
    required this.entry,
    required this.animation,
    required this.request,
  });

  final int id;
  final String? identity;
  final OverlayEntry entry;
  final AnimationController animation;
  final _DialogRequest<Object?> request;

  /// Set once its closing animation has started.
  bool closing = false;
}

/// Barrier plus the dialog, scaled and faded in by [animation].
class _DialogOverlayEntry extends StatelessWidget {
  const _DialogOverlayEntry({
    super.key,
    required this.id,
    required this.request,
    required this.capturedThemes,
    required this.animation,
    required this.onBarrierTap,
  });

  final int id;
  final _DialogRequest<Object?> request;
  final CapturedThemes capturedThemes;
  final Animation<double> animation;
  final VoidCallback onBarrierTap;

  @override
  Widget build(BuildContext context) {
    Widget dialog = _DialogScope(
      id: id,
      child: Builder(
        builder: (dialogContext) =>
            capturedThemes.wrap(request.builder(dialogContext)),
      ),
    );
    if (request.useSafeArea) dialog = SafeArea(child: dialog);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: request.barrierDismissible ? onBarrierTap : null,
            child: Semantics(
              label:
                  request.barrierLabel ??
                  MaterialLocalizations.of(context).modalBarrierDismissLabel,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeIn,
                ),
                child: ColoredBox(
                  color:
                      request.barrierColor ??
                      Theme.of(context).colorScheme.scrim,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: request.transitionCurve,
            ),
            child: Material(type: MaterialType.transparency, child: dialog),
          ),
        ),
      ],
    );
  }
}

/// Carries a dialog's id down to its [OverlayDialogState].
class _DialogScope extends InheritedWidget {
  const _DialogScope({required this.id, required super.child});

  final int id;

  static _DialogScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_DialogScope>();

  @override
  bool updateShouldNotify(_DialogScope oldWidget) => oldWidget.id != id;
}
