part of 'app_dialog_controller.dart';

/// A dialog widget shown through [AppDialogController.show].
abstract class OverlayDialogWidget extends StatefulWidget {
  const OverlayDialogWidget({super.key});

  @override
  OverlayDialogState<OverlayDialogWidget> createState();
}

/// State of an [OverlayDialogWidget]; [closeDialog] closes exactly this
/// dialog.
abstract class OverlayDialogState<T extends OverlayDialogWidget>
    extends State<T> {
  /// The controller's id for the dialog this state is built in, read once
  /// from [_AppDialogScope]. `null` when the widget was built outside
  /// [AppDialogController.show].
  String? _dialogId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dialogId ??= _AppDialogScope.maybeOf(context)?.internalId;
  }

  /// Closes this dialog and completes its [AppDialogController.show] future
  /// with [result].
  ///
  /// Only this dialog: once it is gone — dismissed by the barrier, the system
  /// back or another caller — a late call is a no-op and never closes the
  /// dialog shown after it. A widget built outside [AppDialogController.show]
  /// has no id and closes whichever dialog is visible.
  void closeDialog([dynamic result]) {
    final controller = AppDialogController._instance;
    if (controller == null) return;
    final dialogId = _dialogId;
    if (dialogId != null) {
      controller._dismissInternal<dynamic>(
        internalId: dialogId,
        result: result,
      );
    } else {
      controller._dismissInternal<dynamic>(result: result);
    }
  }

  @override
  Widget build(BuildContext context);
}

/// Carries the controller's id for one dialog down to its
/// [OverlayDialogState], so [OverlayDialogState.closeDialog] dismisses that
/// dialog and no other.
class _AppDialogScope extends InheritedWidget {
  const _AppDialogScope({required this.internalId, required super.child});

  final String internalId;

  static _AppDialogScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppDialogScope>();

  @override
  bool updateShouldNotify(_AppDialogScope oldWidget) =>
      oldWidget.internalId != internalId;
}
