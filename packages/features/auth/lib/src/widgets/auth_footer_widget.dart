import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

/// Authentication footer widget for navigation and secondary actions
///
/// This widget provides a consistent footer design for authentication screens,
/// featuring navigation links between different auth flows (login/register)
/// and optional secondary actions like "Forgot Password". It maintains
/// proper visual hierarchy and follows accessibility guidelines.
///
/// The footer is designed to be flexible and contextual, showing different
/// content based on the current authentication screen. It uses clear,
/// action-oriented language to guide users through the authentication flow.
///
/// Key features:
/// - Contextual navigation between authentication screens
/// - Optional "Forgot Password" link for login screens
/// - Consistent typography and spacing
/// - Theme-aware colors that adapt to light/dark modes
/// - Proper touch targets for accessibility
/// - Clear visual hierarchy with primary and secondary actions
///
/// Design principles:
/// - Uses subtle colors for secondary actions to maintain focus on primary flow
/// - Provides adequate spacing for touch interactions
/// - Follows platform conventions for link styling
/// - Maintains consistency across different authentication screens
///
/// Example usage:
/// ```dart
/// // Login screen footer
/// AuthFooterWidget(
///   questionText: 'Don\'t have an account?',
///   actionText: 'Sign Up',
///   showForgotPassword: true,
///   onActionPressed: () => navigateToRegister(),
///   onForgotPasswordPressed: () => navigateToForgotPassword(),
/// )
///
/// // Register screen footer
/// AuthFooterWidget(
///   questionText: 'Already have an account?',
///   actionText: 'Sign In',
///   onActionPressed: () => navigateToLogin(),
/// )
/// ```
class AuthFooterWidget extends StatelessWidget {
  const AuthFooterWidget({
    super.key,
    required this.questionText,
    required this.actionText,
    this.onActionPressed,
    this.showForgotPassword = false,
    this.forgotPasswordText,
    this.onForgotPasswordPressed,
  });

  /// The contextual question text that precedes the action link
  ///
  /// This should be phrased as a question that naturally leads to the
  /// action, such as "Don't have an account?" or "Already have an account?".
  final String questionText;

  /// The action text for the navigation link
  ///
  /// This should be a clear, action-oriented phrase like "Sign Up",
  /// "Sign In", or "Back to Login" that indicates what will happen
  /// when the user taps the link.
  final String actionText;

  /// Callback function invoked when the main action link is pressed
  ///
  /// This typically handles navigation between authentication screens,
  /// such as moving from login to registration or vice versa.
  final VoidCallback? onActionPressed;

  /// Whether to display the forgot-password link
  ///
  /// Set to true on login screens where users might need password
  /// recovery options. Should be false on other screens to avoid clutter.
  final bool showForgotPassword;

  /// Localized label for the forgot-password link (required when
  /// [showForgotPassword] is true).
  final String? forgotPasswordText;

  /// Callback function invoked when the forgot-password link is pressed
  ///
  /// This should navigate to the password recovery screen. Only used
  /// when [showForgotPassword] is true.
  final VoidCallback? onForgotPasswordPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Forgot password link
        if (showForgotPassword) ...[
          TextButton(
            onPressed: onForgotPasswordPressed,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: context.w(16),
                vertical: context.h(8),
              ),
            ),
            child: Text(
              forgotPasswordText ?? '',
              style: AppTextStyles.bodyMediumStyle(context).copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: context.h(16)),
        ],

        // Question and action
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              questionText,
              style: AppTextStyles.bodyMediumStyle(
                context,
              ).copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: onActionPressed,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: context.w(8)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText,
                style: AppTextStyles.bodyMediumStyle(context).copyWith(
                  color: context.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
