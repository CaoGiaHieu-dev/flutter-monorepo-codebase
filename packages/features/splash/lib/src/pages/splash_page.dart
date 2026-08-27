import 'dart:ui';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Swirling Liquid Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: AppGradients.liquidOnboarding(context),
            ),
          ),
          // High-fidelity Glassmorphic Card Content
          Center(
            child: ClipRRect(
              borderRadius: AppRadius.xxlRadius(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  width: context.w(280),
                  height: context.w(280),
                  padding: EdgeInsets.all(AppSpacing.xl(context)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: AppRadius.xxlRadius(context),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: context.w(1.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: context.r(30),
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Glowing Brand Logo
                      Container(
                        padding: EdgeInsets.all(AppSpacing.md(context)),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.1),
                              blurRadius: context.r(20),
                              spreadRadius: context.r(2),
                            ),
                          ],
                        ),
                        child: FlutterLogo(size: context.w(64)),
                      ),
                      SizedBox(height: AppSpacing.lg(context)),
                      // Styled Premium Typography
                      Text(
                        'Template',
                        style: AppTextStyles.headlineLargeStyle(context)
                            .copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                            ),
                      ),
                      SizedBox(height: AppSpacing.sm(context)),
                      Text(
                        'Clean Codebase Architecture',
                        style: AppTextStyles.bodyMediumStyle(context).copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      // Sleek Spinner
                      SizedBox(
                        width: context.w(24),
                        height: context.w(24),
                        child: CircularProgressIndicator(
                          strokeWidth: context.w(2.5),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
