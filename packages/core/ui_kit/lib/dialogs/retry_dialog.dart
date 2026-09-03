import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

class RetryDialog extends OverlayDialogWidget {
  const RetryDialog({super.key, this.onCancel, this.onRetry});
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  OverlayDialogState<RetryDialog> createState() => _RetryDialogState();
}

class _RetryDialogState extends OverlayDialogState<RetryDialog> {
  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(context.l10n.error_occurred),
      content: Text(context.l10n.try_again),
      actions: [
        CupertinoDialogAction(
          isDestructiveAction: true,
          child: Text(context.l10n.retry),
          onPressed: () {
            closeDialog();
            widget.onCancel?.call();
          },
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            closeDialog();
            widget.onRetry?.call();
          },
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}
