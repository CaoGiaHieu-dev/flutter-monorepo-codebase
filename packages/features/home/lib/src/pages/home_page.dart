import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
                    SizedBox(height: 16.h),
                    Text(
                      isLoggedIn
                          ? context.l10nHome.user_logged_in
                          : context.l10nHome.user_logged_out,
                      style: TextStyle(
                        color: isLoggedIn
                            ? context.colorScheme.primary
                            : context.colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                    ),
                    if (user?.name != null) ...[
                      SizedBox(height: 8.h),
                      Text(user!.name!, style: TextStyle(fontSize: 12.sp)),
                    ],
                    SizedBox(height: 16.h),
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
