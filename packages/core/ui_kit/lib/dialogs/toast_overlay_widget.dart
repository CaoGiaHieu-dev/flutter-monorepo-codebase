import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ToastOverlayWidget extends StatelessWidget {
  const ToastOverlayWidget({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: context.width - (16.w * 2)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4.r),
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 12.h),
          child: Text(
            content,
            style: AppTextStyles.bodyMediumStyle(
              context,
            ).copyWith(fontWeight: FontWeight.w500, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
