import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';

/// SAMPLE — the app's cold-start location, contributed via `IAppEntryLocation`.
///
/// The button reaches auth through `getItOrNull<AuthNavigator>()`, so a build
/// without `feature_auth` still renders this screen; the button simply does
/// nothing. That null-tolerance is what makes a feature removable.
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
              context.l10nOnboarding.welcomeToOnboarding,
              style: AppTextStyles.headlineMediumStyle(context),
            ),
            SizedBox(height: AppSpacing.xlH(context)),
            ElevatedButton(
              onPressed: () {
                getItOrNull<AuthNavigator>()?.toLogin(context);
              },
              child: Text(context.l10nOnboarding.getStarted),
            ),
          ],
        ),
      ),
    );
  }
}
