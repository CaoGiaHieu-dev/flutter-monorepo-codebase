import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_ui_kit/buttons/custom_button.dart';
import 'package:core_ui_kit/dialogs/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../extensions/extensions.dart';
import '../provider/auth_provider.dart';
import '../widgets/auth_footer_widget.dart';
import '../widgets/auth_form_widget.dart';
import '../widgets/auth_header_widget.dart';
import '../widgets/auth_social_widget.dart';

/// User authentication login page with comprehensive form handling
///
/// This page provides a complete login experience with email/password
/// authentication, social login options, and proper error handling.
/// It integrates with the AuthProvider for state management and follows
/// Material Design principles for consistent user experience.
///
/// The page features:
/// - Email and password input with validation
/// - Social authentication options (Google, Apple)
/// - Navigation to registration and password recovery
/// - Loading states during authentication
/// - Error handling with user-friendly messages
/// - Responsive design that adapts to different screen sizes
/// - Accessibility support with proper semantic structure
///
/// User flow:
/// 1. User enters email and password credentials
/// 2. Form validation ensures proper input format
/// 3. Authentication request is processed via AuthProvider
/// 4. Success: Navigate to dashboard/main app
/// 5. Error: Display appropriate error message
/// 6. Alternative: Use social login or navigate to registration
///
/// Example navigation:
/// ```dart
/// // Navigate to login page
/// context.pushNamed('/auth/login');
///
/// // Or using GoRouter
/// context.go('/auth/login');
/// ```
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController(text: '123@gmail.com');
  final _passwordController = TextEditingController(text: '123@gmail.com');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.login(_emailController.text, _passwordController.text);
  }

  void _onRegisterPressed() {
    getItOrNull<AuthNavigator>()?.toRegister(context);
  }

  void _onForgotPasswordPressed() {
    getItOrNull<AuthNavigator>()?.toForgotPassword(context);
  }

  void _onGooglePressed() {
    AppDialog.showInfoDialog(
      title: context.l10nAuth.coming_soon,
      message: context.l10nAuth.google_sign_in_soon,
    );
  }

  void _onApplePressed() {
    AppDialog.showInfoDialog(
      title: context.l10nAuth.coming_soon,
      message: context.l10nAuth.apple_sign_in_soon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.w(24)),
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return Column(
                children: [
                  SizedBox(height: context.h(40)),

                  // Header
                  AuthHeaderWidget(
                    title: context.l10nAuth.welcome_back,
                    subtitle: context.l10nAuth.sign_in_subtitle,
                  ),

                  SizedBox(height: context.h(40)),

                  // Login form
                  AuthFormWidget(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    submitButtonText: context.l10nAuth.sign_in,
                    isLoading: authProvider.isLoading,
                    onSubmit: _onLoginPressed,
                  ),

                  SizedBox(height: context.h(32)),

                  CustomButton.rectangle(
                    onPressed: () {
                      getItOrNull<HomeNavigator>()?.toHome(context);
                    },
                    child: Text(
                      context.l10nAuth.login_as_guest,
                      style: AppTextStyles.bodyLargeStyle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),

                  SizedBox(height: context.h(32)),

                  // Social login
                  AuthSocialWidget(
                    onGooglePressed: _onGooglePressed,
                    onApplePressed: _onApplePressed,
                  ),

                  SizedBox(height: context.h(32)),

                  // Footer
                  AuthFooterWidget(
                    questionText: context.l10nAuth.dont_have_account,
                    actionText: context.l10nAuth.sign_up,
                    showForgotPassword: true,
                    forgotPasswordText: context.l10nAuth.forgot_password,
                    onActionPressed: _onRegisterPressed,
                    onForgotPasswordPressed: _onForgotPasswordPressed,
                  ),

                  SizedBox(height: context.h(40)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
