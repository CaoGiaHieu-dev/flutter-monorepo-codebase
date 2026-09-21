import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/buttons/custom_button.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';

/// SAMPLE — demonstrates a feature-owned form widget:
/// feature-scoped translations (`context.l10nAuth`), `core_responsive` scaling
/// through `BuildContext`, and a `core_ui_kit` button taking *unscaled* values.
///
/// The widget owns validation and nothing else — submitting is the caller's
/// job, so the page keeps the `AuthProvider` call and this stays reusable.
class AuthFormWidget extends StatefulWidget {
  const AuthFormWidget({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.submitButtonText,
    this.onSubmit,
    this.isLoading = false,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final String submitButtonText;

  /// Called only after validation passes.
  final VoidCallback? onSubmit;

  /// Swaps the button label for a spinner and swallows taps.
  final bool isLoading;

  @override
  State<AuthFormWidget> createState() => _AuthFormWidgetState();
}

class _AuthFormWidgetState extends State<AuthFormWidget> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return context.l10nAuth.email_is_required;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return context.l10nAuth.invalid_email;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return context.l10nAuth.password_is_required;
    }
    if (value.length < 6) return context.l10nAuth.password_too_short;
    return null;
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) widget.onSubmit?.call();
  }

  /// One decoration for both fields — the three copies this replaced drifted
  /// apart the moment any one of them was edited.
  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final radius = context.borderRadius(all: 12);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: context.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: context.colorScheme.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: _validateEmail,
            decoration: _decoration(
              label: context.l10nAuth.email,
              hint: context.l10nAuth.enter_your_email,
              icon: Icons.email_outlined,
            ),
          ),
          context.verticalSpace(16),
          TextFormField(
            controller: widget.passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            validator: _validatePassword,
            onFieldSubmitted: (_) => _onSubmit(),
            decoration: _decoration(
              label: context.l10nAuth.password,
              hint: context.l10nAuth.enter_your_password,
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          context.verticalSpace(24),
          CustomButton.rectangle(
            onPressed: () {
              if (widget.isLoading) return;
              _onSubmit();
            },
            child: widget.isLoading
                ? SizedBox(
                    width: context.w(20),
                    height: context.h(20),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.submitButtonText,
                    style: AppTextStyles.bodyLargeStyle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
