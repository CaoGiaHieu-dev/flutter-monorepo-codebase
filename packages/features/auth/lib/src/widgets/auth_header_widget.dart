import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';

/// Authentication header widget for displaying app branding and welcome content
///
/// This widget provides a consistent header design across all authentication
/// screens, featuring an optional app logo, main title, and descriptive subtitle.
/// It follows Material Design principles and integrates seamlessly with the
/// app's theme system.
///
/// The header is designed to create a welcoming first impression and establish
/// brand identity while providing clear context about the current authentication
/// step. The layout is responsive and adapts to different screen sizes.
///
/// Features:
/// - Optional app logo with gradient background
/// - Customizable title and subtitle text
/// - Responsive typography that scales with screen size
/// - Theme-aware colors that adapt to light/dark modes
/// - Proper text overflow handling for long content
/// - Accessibility support with semantic text roles
///
/// Example usage:
/// ```dart
/// AuthHeaderWidget(
///   title: 'Welcome Back',
///   subtitle: 'Sign in to your account to continue',
///   showLogo: true,
/// )
///
/// // For password reset screen
/// AuthHeaderWidget(
///   title: 'Forgot Password?',
///   subtitle: 'Enter your email to receive a reset link',
///   showLogo: false,
/// )
/// ```
class AuthHeaderWidget extends StatelessWidget {
  const AuthHeaderWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.showLogo = true,
  });

  /// The main title text displayed prominently at the top
  ///
  /// This should be a concise, welcoming message that clearly indicates
  /// the purpose of the current screen (e.g., "Welcome Back", "Create Account").
  final String title;

  /// The descriptive subtitle text that provides additional context
  ///
  /// This should explain what the user needs to do or what will happen
  /// next in the authentication flow (e.g., "Sign in to continue").
  final String subtitle;

  /// Whether to display the app logo above the title
  ///
  /// Set to true for main authentication screens (login, register) and
  /// false for secondary screens (forgot password, verification) to
  /// maintain visual hierarchy and reduce clutter.
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: context.w(24)),
      child: Column(
        children: [
          if (showLogo) ...[
            // App logo
            Container(
              width: context.w(120),
              height: context.h(120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(context.r(20)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.colorScheme.primary,
                    context.colorScheme.secondary,
                  ],
                ),
              ),
              child: Icon(
                Icons.lock_outline,
                size: context.r(60),
                color: context.colorScheme.onPrimary,
              ),
            ),
            SizedBox(height: context.h(32)),
          ],

          // Title
          Text(
            title,
            style: AppTextStyles.headlineLargeStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: context.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: context.h(8)),

          // Subtitle
          Text(
            subtitle,
            style: AppTextStyles.bodyLargeStyle(context).copyWith(
              color: context.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
