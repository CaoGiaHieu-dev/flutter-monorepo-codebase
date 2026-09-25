import 'package:core_base_ui/core_base_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

import 'app_overlay.dart';

/// Asks whether to retry after a request failed on the network; shown by the
/// shell's `NetworkConfig.onRetryCallback` through [AppOverlay.showDialog].
///
/// Closes itself before calling [onCancel] / [onRetry].
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
      title: Text(context.l10n.errorOccurred),
      content: Text(context.l10n.tryAgain),
      actions: [
        CupertinoDialogAction(
          onPressed: () {
            closeDialog();
            widget.onCancel?.call();
          },
          child: Text(context.l10n.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            closeDialog();
            widget.onRetry?.call();
          },
          child: Text(context.l10n.retry),
        ),
      ],
    );
  }
}
