import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../extensions/extensions.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10nOnboarding.welcome_to_onboarding,
              style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24.h),
            ElevatedButton(
              onPressed: () {
                getItOrNull<AuthNavigator>()?.toLogin(context);
              },
              child: Text(context.l10nOnboarding.get_started),
            ),
          ],
        ),
      ),
    );
  }
}
