import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

import '../bloc/home_profile_bloc.dart';
import '../extensions/extensions.dart';

/// Home tab — sample screen using a route-scoped [HomeProfileBloc].
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: BlocBuilder<HomeProfileBloc, BlocViewState<UserEntity?>>(
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
                    SizedBox(height: context.h(16)),
                    Text(
                      isLoggedIn
                          ? context.l10nHome.user_logged_in
                          : context.l10nHome.user_logged_out,
                      style: TextStyle(
                        color: isLoggedIn
                            ? context.colorScheme.primary
                            : context.colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: context.sp(14),
                      ),
                    ),
                    if (user?.name != null) ...[
                      SizedBox(height: context.h(8)),
                      Text(
                        user!.name!,
                        style: TextStyle(fontSize: context.sp(12)),
                      ),
                    ],
                    SizedBox(height: context.h(16)),
                    TextButton(
                      onPressed: () => context.read<HomeProfileBloc>().add(
                        const HomeProfileEvent.refreshed(),
                      ),
                      child: Text(context.l10nHome.refresh_profile),
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
