import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../extensions/l10n_home_extension.dart';

/// Home tab: renders the route-scoped [HomeProfileBloc]'s state.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Centred, and scrolls instead of overflowing at large text sizes.
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: BlocBuilder<HomeProfileBloc, BlocViewState<SessionPrincipal?>>(
            builder: (context, state) => state.when(
              initial: () => const SizedBox.shrink(),
              loading: () => const CircularProgressIndicator(),
              success: (user) => Column(
                children: [
                  Text(
                    user == null
                        ? context.l10nHome.userLoggedOut
                        : context.l10nHome.userLoggedIn,
                    style: AppTextStyles.bodyMediumStyle(context),
                  ),
                  if (user?.displayName case final name?) Text(name),
                  SizedBox(height: AppSpacing.mdH(context)),
                  TextButton(
                    onPressed: () => context.read<HomeProfileBloc>().add(
                      const HomeProfileEvent.refreshed(),
                    ),
                    child: Text(context.l10nHome.refreshProfile),
                  ),
                ],
              ),
              // `failure.message` is developer text (RULE-34): show the
              // translated sentence for its code.
              error: (failure) =>
                  Text(context.l10n.failureMessage(failure.code)),
            ),
          ),
        ),
      ),
    );
  }
}
