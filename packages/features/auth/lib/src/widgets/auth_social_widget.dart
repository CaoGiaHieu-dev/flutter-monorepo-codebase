import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';

import '../extensions/extensions.dart';

/// Social authentication widget for third-party login options.
class AuthSocialWidget extends StatelessWidget {
  const AuthSocialWidget({
    super.key,
    this.onGooglePressed,
    this.onApplePressed,
    this.onFacebookPressed,
  });

  final VoidCallback? onGooglePressed;
  final VoidCallback? onApplePressed;
  final VoidCallback? onFacebookPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Divider(
                color: context.colorScheme.outline.withAlpha(0.3.toOpacity),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.w(16)),
              child: Text(
                context.l10nAuth.or_divider,
                style: AppTextStyles.bodySmallStyle(context).copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: context.colorScheme.outline.withAlpha(0.3.toOpacity),
              ),
            ),
          ],
        ),
        SizedBox(height: context.h(24)),
        Column(
          children: [
            if (onGooglePressed != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onGooglePressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: context.h(16)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.r(12)),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.g_mobiledata,
                    size: context.r(24),
                    color: context.colorScheme.onSurface,
                  ),
                  label: Text(
                    context.l10nAuth.continue_with_google,
                    style: AppTextStyles.bodyLargeStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            if (onApplePressed != null) ...[
              SizedBox(height: context.h(12)),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onApplePressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: context.h(16)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.r(12)),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.apple,
                    size: context.r(24),
                    color: context.colorScheme.onSurface,
                  ),
                  label: Text(
                    context.l10nAuth.continue_with_apple,
                    style: AppTextStyles.bodyLargeStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
            if (onFacebookPressed != null) ...[
              SizedBox(height: context.h(12)),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onFacebookPressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: context.h(16)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.r(12)),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.facebook,
                    size: context.r(24),
                    color: context.colorScheme.onSurface,
                  ),
                  label: Text(
                    context.l10nAuth.continue_with_facebook,
                    style: AppTextStyles.bodyLargeStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
