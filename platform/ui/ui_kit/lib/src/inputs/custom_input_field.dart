import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/shared_ui_constants.dart';

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
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onTap;
  final TextStyle? hintStyle;
  final double? paddingBottom;
  final bool obscureText;

  @override
  State<CustomInputField> createState() => _CustomInputFieldState();
}

class _CustomInputFieldState extends State<CustomInputField> {
  /// Created only when the caller passes no [CustomInputField.focusNode]; this
  /// state owns — and must dispose — that node alone, never the caller's.
  FocusNode? _ownedFocusNode;

  FocusNode get focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void didUpdateWidget(CustomInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switched to a caller-provided node: the one we created is now unused.
    if (widget.focusNode != null && _ownedFocusNode != null) {
      _ownedFocusNode!.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border =
        widget.border ??
        OutlineInputBorder(
          borderRadius: AppRadius.mdRadius(context),
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
              // The counter sits at the end of the field; nudge it back
              // towards the start — leftwards in LTR, rightwards in RTL.
              final isRtl = Directionality.of(context) == TextDirection.rtl;
              return Container(
                padding: EdgeInsets.only(
                  bottom:
                      widget.paddingBottom ??
                      context.h(SharedUiConstants.INPUT_COUNTER_OFFSET_X),
                ),
                transform: Matrix4.translationValues(
                  (isRtl ? 1 : -1) *
                      context.w(SharedUiConstants.INPUT_COUNTER_OFFSET_X),
                  -context.h(SharedUiConstants.INPUT_COUNTER_OFFSET_Y),
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
            ? Padding(
                padding: EdgeInsetsDirectional.only(
                  start: AppSpacing.md(context),
                ),
              )
            : null,
        suffix: widget.suffixIcon == null
            ? Padding(
                padding: EdgeInsetsDirectional.only(
                  end: AppSpacing.md(context),
                ),
              )
            : null,
        contentPadding:
            widget.contentPadding ??
            EdgeInsets.symmetric(vertical: AppSpacing.mdH(context)),
      ),
    );
  }
}
