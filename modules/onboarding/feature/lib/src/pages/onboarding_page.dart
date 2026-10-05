import 'package:auth_api/auth_api.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:home_api/home_api.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/l10n_onboarding_extension.dart';

/// SAMPLE — the app's cold-start location, contributed via `IAppEntryLocation`.
///
/// The button reaches auth through `getItOrNull<AuthNavigator>()` and falls
/// back to `HomeNavigator` when `feature_auth` is not composed; with neither
/// it does nothing. Both navigators come from `*_api` packages, never from
/// another feature (arch_check R3), which is what keeps a module removable.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Centred when it fits, scrolls instead of overflowing when it does not.
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                context.l10nOnboarding.welcomeToOnboarding,
                style: AppTextStyles.headlineMediumStyle(context),
                textAlign: TextAlign.center,
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
      ),
    );
  }
}
