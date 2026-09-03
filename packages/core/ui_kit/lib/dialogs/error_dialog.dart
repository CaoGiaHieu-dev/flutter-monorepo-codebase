import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';

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
          padding: context.edgeInsets(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: context.borderRadius(all: 8),
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
              SizedBox(height: context.h(8)),
              Text(
                widget.content,
                style: AppTextStyles.bodyMediumStyle(
                  context,
                ).copyWith(fontSize: context.sp(13), color: context.colors.textPrimary),
              ),
              SizedBox(height: context.h(20)),
              CustomButton.rectangle(
                height: context.h(40),
                minWidth: ButtonTheme.of(context).minWidth,
                onPressed: () {
                  closeDialog();
                  widget.onConfirm?.call();
                },
                radius: context.r(4),
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
