import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          borderRadius: context.borderRadius(all: 8),
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
                padding: EdgeInsets.only(
                  bottom: widget.paddingBottom ?? context.h(10),
                ),
                transform: Matrix4.translationValues(
                  -context.h(10),
                  -context.h(30),
                  0,
                ),
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
            ? Padding(padding: EdgeInsetsDirectional.only(start: context.w(12)))
            : null,
        suffix: widget.suffixIcon == null
            ? Padding(padding: EdgeInsetsDirectional.only(end: context.w(12)))
            : null,
        contentPadding:
            widget.contentPadding ?? context.edgeInsets(vertical: 11),
      ),
    );
  }
}
