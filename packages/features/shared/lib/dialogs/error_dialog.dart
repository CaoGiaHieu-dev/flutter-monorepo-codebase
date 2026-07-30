import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../buttons/custom_button.dart';

class ErrorDialog extends OverlayDialogWidget {
  const ErrorDialog({
    required this.title,
    required this.content,
    this.onConfirm,
  });

  final String title;
  final String content;
  final VoidCallback? onConfirm;

  @override
  OverlayDialogState<OverlayDialogWidget> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends OverlayDialogState<ErrorDialog> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: context.colors.surface,
        surfaceTintColor: context.colors.surface,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.r),
            color: context.colors.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: AppTextStyles.bodyMediumStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                widget.content,
                style: AppTextStyles.bodyMediumStyle(
                  context,
                ).copyWith(fontSize: 13.sp, color: context.colors.textPrimary),
              ),
              SizedBox(height: 20.h),
              CustomButton.rectangle(
                height: 40.h,
                minWidth: ButtonTheme.of(context).minWidth,
                onPressed: () {
                  closeDialog();
                  widget.onConfirm?.call();
                },
                radius: 4.r,
                color: context.primary,
                child: Text(
                  context.l10n.ok,
                  style: AppTextStyles.bodyLargeStyle(context).copyWith(
                    color: context.colors.surface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
