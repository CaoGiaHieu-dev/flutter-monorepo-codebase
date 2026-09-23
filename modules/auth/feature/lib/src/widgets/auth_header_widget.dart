import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

/// SAMPLE — demonstrates the `_widget.dart` / `Widget` suffix convention and
/// design-token usage (`AppTextStyles`, `context.colorScheme`, `context.w/h/r`).
///
/// Nothing here is auth-specific; it is a titled header. Delete it with the
/// rest of the auth sample.
class AuthHeaderWidget extends StatelessWidget {
  const AuthHeaderWidget({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          // Same scale on both axes, or the square stretches on a wide
          // window: `r` scales by the smaller of the two factors.
          width: context.r(96),
          height: context.r(96),
          decoration: BoxDecoration(
            borderRadius: AppRadius.xlRadius(context),
            color: context.colorScheme.primaryContainer,
          ),
          child: Icon(
            Icons.lock_outline,
            size: context.r(44),
            color: context.colorScheme.onPrimaryContainer,
          ),
        ),
        SizedBox(height: AppSpacing.xlH(context)),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLargeStyle(
            context,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: AppSpacing.smH(context)),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyLargeStyle(
            context,
          ).copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
