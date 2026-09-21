import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../extensions/extensions.dart';

/// Home tab — sample screen using a route-scoped [HomeProfileBloc].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: BlocBuilder<HomeProfileBloc, BlocViewState<AuthPrincipal?>>(
          builder: (context, state) {
            return state.when(
              initial: () => const SizedBox.shrink(),
              loading: () => const CircularProgressIndicator(),
              success: (user) {
                final isLoggedIn = user != null;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.l10nHome.home),
                    SizedBox(height: AppSpacing.mdH(context)),
                    Text(
                      isLoggedIn
                          ? context.l10nHome.userLoggedIn
                          : context.l10nHome.userLoggedOut,
                      style: AppTextStyles.bodyMediumStyle(context).copyWith(
                        color: isLoggedIn
                            ? context.colorScheme.primary
                            : context.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (user?.displayName != null) ...[
                      SizedBox(height: AppSpacing.smH(context)),
                      Text(
                        user!.displayName!,
                        style: AppTextStyles.bodySmallStyle(context),
                      ),
                    ],
                    SizedBox(height: AppSpacing.mdH(context)),
                    TextButton(
                      onPressed: () => context.read<HomeProfileBloc>().add(
                        const HomeProfileEvent.refreshed(),
                      ),
                      child: Text(context.l10nHome.refreshProfile),
                    ),
                  ],
                );
              },
              error: (failure) => Text(failure.message),
            );
          },
        ),
      ),
    );
  }
}
