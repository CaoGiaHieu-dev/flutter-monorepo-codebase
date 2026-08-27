import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CustomInputField extends StatefulWidget {
  const CustomInputField({
    super.key,
    this.controller,
    this.validator,
    this.hintText,
    this.prefixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.showCounter = false,
    this.inputFormatters = const [],
    this.maxLength = 255,
    this.suffixIcon,
    this.border,
    this.contentPadding,
    this.enable = true,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    this.closeWhenTapOutside = true,
    this.onTap,
    this.hintStyle,
    this.paddingBottom,
    this.obscureText = false,
  });
  final TextEditingController? controller;
  final String? Function(String? value)? validator;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final bool showCounter;
  final bool closeWhenTapOutside;
  final bool enable;
  final List<TextInputFormatter> inputFormatters;
  final int maxLength;
  final InputBorder? border;
  final EdgeInsetsGeometry? contentPadding;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged? onFieldSubmitted;
  final VoidCallback? onTap;
  final TextStyle? hintStyle;
  final double? paddingBottom;
  final bool obscureText;

  @override
  State<CustomInputField> createState() => _CustomInputFieldState();
}

class _CustomInputFieldState extends State<CustomInputField> {
  late FocusNode focusNode;

  @override
  void initState() {
    focusNode = widget.focusNode ?? FocusNode();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final border =
        widget.border ??
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: context.colors.surfaceVariant),
        );
    return TextFormField(
      enabled: widget.enable,
      focusNode: focusNode,
      obscureText: widget.obscureText,
      buildCounter:
          (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) {
            if (widget.showCounter) {
              return Container(
                padding: EdgeInsets.only(bottom: widget.paddingBottom ?? 10.h),
                transform: Matrix4.translationValues(-10.h, -30.h, 0),
                child: Text(
                  '$currentLength/$maxLength',
                  style: AppTextStyles.labelMediumStyle(
                    context,
                  ).copyWith(color: context.colors.textSecondary),
                ),
              );
            }
            return const SizedBox();
          },
      autovalidateMode: AutovalidateMode.onUserInteraction,
      maxLength: widget.maxLength,
      controller: widget.controller,
      cursorColor: context.colors.textPrimary,
      cursorErrorColor: context.colors.textPrimary,
      style: AppTextStyles.bodyMediumStyle(context),
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      minLines: widget.minLines,
      textInputAction: widget.textInputAction,
      onTap: widget.onTap,
      onFieldSubmitted: (value) {
        widget.onFieldSubmitted?.call(value);
      },
      onTapOutside: (event) {
        if (widget.closeWhenTapOutside) {
          focusNode.unfocus();
        }
      },
      maxLines: widget.maxLines,
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle:
            widget.hintStyle ??
            AppTextStyles.bodyMediumStyle(
              context,
            ).copyWith(color: context.colors.textDisabled),
        errorStyle: AppTextStyles.labelMediumStyle(
          context,
        ).copyWith(color: context.colors.error),
        border: border,
        enabledBorder: border,
        errorBorder: border,
        isDense: true,
        focusedBorder: border,
        disabledBorder: border,
        suffixIcon: widget.suffixIcon,
        prefixIcon: widget.prefixIcon,
        suffixIconConstraints: const BoxConstraints(),
        prefixIconConstraints: const BoxConstraints(),
        focusedErrorBorder: border,
        fillColor: context.colors.surface,
        filled: true,
        prefix: widget.prefixIcon == null
            ? Padding(padding: EdgeInsetsDirectional.only(start: 12.w))
            : null,
        suffix: widget.suffixIcon == null
            ? Padding(padding: EdgeInsetsDirectional.only(end: 12.w))
            : null,
        contentPadding:
            widget.contentPadding ?? EdgeInsets.symmetric(vertical: 11.h),
      ),
    );
  }
}

// ==========================================
// 🛠️ Interactive Previews (Flutter 3.44+)
// ==========================================

@Preview(name: 'Email Input Field', group: 'Shared Inputs')
Widget customInputFieldTextPreview() {
  return const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: CustomInputField(
          hintText: 'Enter your email address',
          prefixIcon: Icon(Icons.email_outlined),
          keyboardType: TextInputType.emailAddress,
        ),
      ),
    ),
  );
}

@Preview(name: 'Secure Password Input', group: 'Shared Inputs')
Widget customInputFieldPasswordPreview() {
  return const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: CustomInputField(
          hintText: 'Enter secure password',
          prefixIcon: Icon(Icons.lock_outline),
          obscureText: true,
          showCounter: true,
          maxLength: 20,
        ),
      ),
    ),
  );
}
