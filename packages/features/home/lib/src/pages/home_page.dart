import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_auth/domain_auth.dart';
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
                    SizedBox(height: context.h(24)),
                    ElevatedButton.icon(
                      onPressed: () {
                        final paymentNav = getItOrNull<PaymentNavigator>();
                        if (paymentNav != null) {
                          paymentNav.toPayment(
                            context,
                            orderId: 'ORD-SUPERAPP-2026',
                            amount: 149.99,
                          );
                        } else {
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(
                                    Icons.extension_off_outlined,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Module Not Loaded'),
                                ],
                              ),
                              content: const Text(
                                'Tính năng Thanh toán (Payment) chưa được kích hoạt trong bản build này (getItOrNull == null).\n\n'
                                'Khi submodule feature_payment được nạp, GetIt sẽ tự động nhận diện và mở giao diện thanh toán thật.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Đóng'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.payment),
                      label: const Text('Thanh toán (Test getItOrNull)'),
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
