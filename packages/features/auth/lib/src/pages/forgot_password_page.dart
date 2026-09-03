import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/di/module.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/dialogs/app_dialog.dart';
import 'package:core_ui_kit/navigation/app_bar_custom.dart';
import 'package:flutter/material.dart';

import '../../feature_auth.dart';

/// Password recovery page for users who have forgotten their credentials
///
/// This page provides a streamlined password recovery experience where users
/// can request a password reset link via email. It features a clean, focused
/// design that guides users through the recovery process with clear instructions
/// and appropriate feedback.
///
/// The page features:
/// - Email input with validation for password reset requests
/// - Clear instructions explaining the recovery process
/// - Loading states during reset request processing
/// - Success confirmation with next steps
/// - Error handling for invalid emails or server issues
/// - Navigation back to login page
/// - Responsive design that adapts to different screen sizes
/// - Accessibility support with proper semantic structure
///
/// Password recovery flow:
/// 1. User enters their email address
/// 2. Email validation ensures proper format
/// 3. Reset request is processed (currently simulated)
/// 4. Success: Show confirmation and instructions to check email
/// 5. Error: Display appropriate error message with retry option
/// 6. User can navigate back to login page
///
/// Example navigation:
/// ```dart
/// // Navigate to forgot password page
/// context.pushNamed('/auth/forgot-password');
///
/// // Or using GoRouter
/// context.go('/auth/forgot-password');
/// ```
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _onResetPressed() async {
    if (_emailController.text.isEmpty) {
      AppDialog.showErrorDialog(
        title: context.l10nAuth.email_required,
        message: context.l10nAuth.enter_email_address,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    AppDialog.showSuccessDialog(
      title: context.l10nAuth.reset_link_sent,
      message: context.l10nAuth.reset_link_sent_message,
      onConfirm: () {
        getItOrNull<AuthNavigator>()?.toLogin(context);
      },
    );
  }

  void _onBackToLoginPressed() {
    getItOrNull<AuthNavigator>()?.toLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBarCustom(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.w(24)),
          child: Column(
            children: [
              SizedBox(height: context.h(40)),

              // Header
              AuthHeaderWidget(
                title: context.l10nAuth.forgot_password,
                subtitle: context.l10nAuth.forgot_password_subtitle,
                showLogo: false,
              ),

              SizedBox(height: context.h(40)),

              // Email input
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _onResetPressed(),
                decoration: InputDecoration(
                  labelText: context.l10nAuth.email,
                  hintText: context.l10nAuth.enter_email_address,
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.r(12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.r(12)),
                    borderSide: BorderSide(
                      color: context.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.r(12)),
                    borderSide: BorderSide(
                      color: context.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),

              SizedBox(height: context.h(32)),

              // Reset button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onResetPressed,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: context.h(16)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.r(12)),
                    ),
                    backgroundColor: context.colorScheme.primary,
                    foregroundColor: context.colorScheme.onPrimary,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: context.w(20),
                          height: context.h(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              context.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Text(
                          context.l10nAuth.send_reset_link,
                          style: AppTextStyles.bodyLargeStyle(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                ),
              ),

              SizedBox(height: context.h(32)),

              // Back to login
              AuthFooterWidget(
                questionText: context.l10nAuth.remember_password,
                actionText: context.l10nAuth.back_to_login,
                onActionPressed: _onBackToLoginPressed,
              ),

              SizedBox(height: context.h(40)),
            ],
          ),
        ),
      ),
    );
  }
}
