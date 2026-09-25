import 'package:auth_api/auth_api.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:home_api/home_api.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/l10n_onboarding_extension.dart';

/// SAMPLE — the app's cold-start location, contributed via `IAppEntryLocation`.
///
/// The button reaches auth through `getItOrNull<AuthNavigator>()` and, in a
/// build without `feature_auth`, falls back to `HomeNavigator` — so first
/// launch never strands the user here. Only with neither module composed does
/// it do nothing. That null-tolerance is what makes a feature removable.
///
/// Both navigators come from the owning modules' API packages (`auth_api`,
/// `home_api`), never from `feature_auth` / `feature_home`: a feature may
/// depend on another module's `*_api` only (arch_check R3). Removing the auth
/// module keeps `auth_api` while this package still imports it
/// (`remove_sample` reports it), so the lookup above still compiles.
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
                final auth = getItOrNull<AuthNavigator>();
                if (auth != null) {
                  auth.toLogin(context);
                } else {
                  getItOrNull<HomeNavigator>()?.toHome(context);
                }
              },
              child: Text(context.l10nOnboarding.getStarted),
            ),
          ],
        ),
      ),
    );
  }
}
