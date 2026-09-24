import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

class ToastOverlayWidget extends StatelessWidget {
  const ToastOverlayWidget({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: context.width - (context.w(16) * 2),
          ),
          decoration: BoxDecoration(
            borderRadius: context.borderRadius(all: 4),
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          padding: context.edgeInsets(horizontal: 28, vertical: 12),
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
