import 'package:core_base_ui/core_base_ui.dart';
import 'package:feature_shared/feature_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../extensions/extensions.dart';

/// Authentication form widget with comprehensive input validation and user experience
///
/// This widget provides a complete authentication form with email and password
/// fields, including optional password confirmation for registration flows.
/// It features comprehensive validation, secure password handling, and
/// accessibility support.
///
/// The form is designed to provide excellent user experience with:
/// - Real-time validation feedback
/// - Secure password visibility toggling
/// - Proper keyboard navigation and input actions
/// - Loading states during form submission
/// - Responsive design that adapts to different screen sizes
/// - Theme-aware styling with consistent visual design
///
/// Key features:
/// - Email validation with regex pattern matching
/// - Password strength requirements (minimum 6 characters)
/// - Password confirmation matching for registration
/// - Secure text input with visibility toggle
/// - Form validation with user-friendly error messages
/// - Loading state management with disabled submit button
/// - Keyboard navigation support (Next/Done actions)
/// - Accessibility labels and semantic structure
///
/// Example usage:
/// ```dart
/// // Login form
/// AuthFormWidget(
///   emailController: emailController,
///   passwordController: passwordController,
///   submitButtonText: 'Sign In',
///   isLoading: authProvider.isLoading,
///   onSubmit: () => handleLogin(),
/// )
///
/// // Registration form with password confirmation
/// AuthFormWidget(
///   emailController: emailController,
///   passwordController: passwordController,
///   confirmPasswordController: confirmPasswordController,
///   showConfirmPassword: true,
///   submitButtonText: 'Create Account',
///   isLoading: authProvider.isLoading,
///   onSubmit: () => handleRegistration(),
/// )
/// ```
class AuthFormWidget extends StatefulWidget {
  const AuthFormWidget({
    super.key,
    required this.emailController,
    required this.passwordController,
    this.confirmPasswordController,
    this.onSubmit,
    this.isLoading = false,
    this.showConfirmPassword = false,
    this.submitButtonText = 'Submit',
  });

  /// Text editing controller for the email input field
  ///
  /// This controller manages the email input state and should be provided
  /// by the parent widget to access the entered email value.
  final TextEditingController emailController;

  /// Text editing controller for the password input field
  ///
  /// This controller manages the password input state and should be provided
  /// by the parent widget to access the entered password value.
  final TextEditingController passwordController;

  /// Text editing controller for the password confirmation field
  ///
  /// This optional controller is only used when [showConfirmPassword] is true,
  /// typically for registration flows where password confirmation is required.
  final TextEditingController? confirmPasswordController;

  /// Callback function invoked when the form is submitted
  ///
  /// This function is called after successful form validation when the user
  /// taps the submit button or presses the done key on the keyboard.
  final VoidCallback? onSubmit;

  /// Whether the form is currently in a loading state
  ///
  /// When true, the submit button shows a loading indicator and is disabled
  /// to prevent multiple submissions during authentication processing.
  final bool isLoading;

  /// Whether to display the password confirmation field
  ///
  /// Set to true for registration flows where users need to confirm their
  /// password. When true, [confirmPasswordController] must also be provided.
  final bool showConfirmPassword;

  /// The text displayed on the submit button
  ///
  /// This should clearly indicate the action being performed, such as
  /// "Sign In", "Create Account", or "Reset Password".
  final String submitButtonText;

  @override
  State<AuthFormWidget> createState() => _AuthFormWidgetState();
}

class _AuthFormWidgetState extends State<AuthFormWidget> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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
    if (value.length < 6) {
      return context.l10nAuth.password_too_short;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!widget.showConfirmPassword) return null;

    if (value == null || value.isEmpty) {
      return context.l10nAuth.confirm_password_required;
    }
    if (value != widget.passwordController.text) {
      return context.l10nAuth.passwords_do_not_match;
    }
    return null;
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSubmit?.call();
    }
  }

  /// Clears validation error messages across all form fields without resetting their text values.
  /// Uses the new clearError() API introduced in Flutter 3.44.0.
  void clearValidationErrors() {
    _formKey.currentState?.clearError();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Email field
          TextFormField(
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: _validateEmail,
            decoration: InputDecoration(
              labelText: context.l10nAuth.email,
              hintText: context.l10nAuth.enter_your_email,
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(
                  color: context.colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(
                  color: context.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // Password field
          TextFormField(
            controller: widget.passwordController,
            obscureText: _obscurePassword,
            textInputAction: widget.showConfirmPassword
                ? TextInputAction.next
                : TextInputAction.done,
            validator: _validatePassword,
            onFieldSubmitted: widget.showConfirmPassword
                ? null
                : (_) => _onSubmit(),
            decoration: InputDecoration(
              labelText: context.l10nAuth.password,
              hintText: context.l10nAuth.enter_your_password,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(
                  color: context.colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(
                  color: context.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),

          // Confirm password field (if needed)
          if (widget.showConfirmPassword) ...[
            SizedBox(height: 16.h),
            TextFormField(
              controller: widget.confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              validator: _validateConfirmPassword,
              onFieldSubmitted: (_) => _onSubmit(),
              decoration: InputDecoration(
                labelText: context.l10nAuth.confirm_password,
                hintText: context.l10nAuth.confirm_password_required,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(
                    color: context.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(
                    color: context.colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],

          SizedBox(height: 24.h),

          // Submit button
          CustomButton.rectangle(
            onPressed: () {
              if (widget.isLoading) return;
              _onSubmit();
            },
            child: widget.isLoading
                ? SizedBox(
                    width: 20.w,
                    height: 20.h,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colorScheme.onPrimary,
                      ),
                    ),
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
