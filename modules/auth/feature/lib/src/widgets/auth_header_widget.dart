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
          width: context.w(96),
          height: context.h(96),
          decoration: BoxDecoration(
            borderRadius: context.borderRadius(all: 20),
            color: context.colorScheme.primaryContainer,
          ),
          child: Icon(
            Icons.lock_outline,
            size: context.r(44),
            color: context.colorScheme.onPrimaryContainer,
          ),
        ),
        context.verticalSpace(24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLargeStyle(
            context,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        context.verticalSpace(8),
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
