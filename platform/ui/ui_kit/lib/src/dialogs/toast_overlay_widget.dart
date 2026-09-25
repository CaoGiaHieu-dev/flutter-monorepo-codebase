import 'package:core_base_ui/core_base_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

/// The toast `AppOverlay.showToast` inserts: [content] on a pill centred on
/// the screen.
class ToastOverlayWidget extends StatelessWidget {
  const ToastOverlayWidget({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.sizeOf(context).width - AppSpacing.lg(context) * 2,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smRadius(context),
            color: context.colors.textPrimary.withValues(
              alpha: SharedUiConstants.TOAST_BACKGROUND_ALPHA,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl(context),
            vertical: AppSpacing.mdH(context),
          ),
          child: Text(
            content,
            // `surface`, not `Colors.white`. The pill's background is
            // `textPrimary`, which inverts with the theme — so the label has
            // to invert with it, or dark mode puts white text on a light
            // pill.
            style: AppTextStyles.bodyMediumStyle(context).copyWith(
              fontWeight: FontWeight.w500,
              color: context.colors.surface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
