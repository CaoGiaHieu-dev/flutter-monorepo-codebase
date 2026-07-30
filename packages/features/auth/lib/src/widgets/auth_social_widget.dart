import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
              padding: EdgeInsets.symmetric(horizontal: 16.w),
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
        SizedBox(height: 24.h),
        Column(
          children: [
            if (onGooglePressed != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onGooglePressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.g_mobiledata,
                    size: 24.r,
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
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onApplePressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.apple,
                    size: 24.r,
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
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onFacebookPressed,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    side: BorderSide(
                      color: context.colorScheme.outline.withAlpha(
                        0.5.toOpacity,
                      ),
                    ),
                  ),
                  icon: Icon(
                    Icons.facebook,
                    size: 24.r,
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
