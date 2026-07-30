import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:feature_shared/dialogs/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../extensions/extensions.dart';
import '../provider/auth_provider.dart';
import '../widgets/auth_footer_widget.dart';
import '../widgets/auth_form_widget.dart';
import '../widgets/auth_header_widget.dart';
import '../widgets/auth_social_widget.dart';

/// User registration page for creating new accounts
///
/// This page provides a comprehensive registration experience with email/password
/// account creation, password confirmation, social registration options, and
/// proper validation. It integrates with the AuthProvider for state management
/// and follows Material Design principles for consistent user experience.
///
/// The page features:
/// - Email and password input with comprehensive validation
/// - Password confirmation to ensure accuracy
/// - Social registration options (Google, Apple)
/// - Navigation to login page for existing users
/// - Loading states during account creation
/// - Success/error handling with appropriate user feedback
/// - Responsive design that adapts to different screen sizes
/// - Accessibility support with proper semantic structure
///
/// Registration flow:
/// 1. User enters email, password, and password confirmation
/// 2. Form validation ensures proper input format and password matching
/// 3. Registration request is processed (currently shows success dialog)
/// 4. Success: Navigate to login page or directly to main app
/// 5. Error: Display appropriate error message with retry options
/// 6. Alternative: Use social registration or navigate to login
///
/// Example navigation:
/// ```dart
/// // Navigate to registration page
/// context.pushNamed('/auth/register');
///
/// // Or using GoRouter
/// context.go('/auth/register');
/// ```
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onRegisterPressed() async {
    // For now, just show a success message
    AppDialog.showSuccessDialog(
      title: context.l10nAuth.registration_successful,
      message: context.l10nAuth.registration_success_message,
      onConfirm: () {
        getItOrNull<AuthNavigator>()?.toLogin(context);
      },
    );
  }

  void _onLoginPressed() {
    getItOrNull<AuthNavigator>()?.toLogin(context);
  }

  void _onGooglePressed() {}

  void _onApplePressed() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return Column(
                children: [
                  SizedBox(height: 40.h),

                  // Header
                  AuthHeaderWidget(
                    title: context.l10nAuth.create_account,
                    subtitle: context.l10nAuth.sign_up_subtitle,
                  ),

                  SizedBox(height: 40.h),

                  // Registration form
                  AuthFormWidget(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    confirmPasswordController: _confirmPasswordController,
                    showConfirmPassword: true,
                    submitButtonText: context.l10nAuth.create_account,
                    isLoading: authProvider.isLoading,
                    onSubmit: _onRegisterPressed,
                  ),

                  SizedBox(height: 32.h),

                  // Social registration
                  AuthSocialWidget(
                    onGooglePressed: _onGooglePressed,
                    onApplePressed: _onApplePressed,
                  ),

                  SizedBox(height: 32.h),

                  // Footer
                  AuthFooterWidget(
                    questionText: context.l10nAuth.already_have_account,
                    actionText: context.l10nAuth.sign_in,
                    onActionPressed: _onLoginPressed,
                  ),

                  SizedBox(height: 40.h),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
