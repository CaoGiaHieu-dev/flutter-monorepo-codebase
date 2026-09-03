import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

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
              style: TextStyle(
                fontSize: context.sp(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: context.h(24)),
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
