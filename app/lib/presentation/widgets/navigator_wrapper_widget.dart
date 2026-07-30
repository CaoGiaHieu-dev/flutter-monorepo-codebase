import 'package:core_common/di/module.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_shared/dialogs/app_overlay.dart';
import 'package:flutter/material.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../providers/deeplink_provider.dart';

class NavigatorWrapperWidget extends StatefulWidget {
  final Widget child;

  const NavigatorWrapperWidget({required this.child});

  @override
  State<NavigatorWrapperWidget> createState() => NavigatorWrapperWidgetState();
}

class NavigatorWrapperWidgetState extends State<NavigatorWrapperWidget> {
  final authProvider = getIt<AuthProvider>();
  final deeplinkProvider = getIt<DeeplinkProvider>();

  /// Boot redirect owns the first navigation. Listener handles later
  /// login/logout transitions only.
  bool _bootCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.endOfFrame.whenComplete(() async {
      await authProvider.ensureInitialized();
      if (!mounted) return;

      final isGoToOnboarding = _goToOnboarding();
      if (isGoToOnboarding) {
        _bootCompleted = true;
        return;
      }

      final isGoToLogin = _goToLogin();
      if (isGoToLogin) {
        _bootCompleted = true;
        return;
      }

      _goToHome();
      deeplinkProvider.initAppLink();
      _bootCompleted = true;
    });
  }

  bool _goToOnboarding() {
    try {
      if (authProvider.data != null) {
        return false;
      }
      final viewed = getIt<StorageValuePresets>().viewedOnboard.value ?? false;
      return !viewed;
    } finally {
      getIt<StorageValuePresets>().viewedOnboard.value = true;
    }
  }

  bool _goToLogin() {
    if (authProvider.data == null) {
      getIt<AuthNavigator>().toLogin(context);
      return true;
    }
    return false;
  }

  void _goToHome() {
    getIt<HomeNavigator>().toHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(
      child: ProviderStateListener<AuthProvider, UserEntity>(
        listenWhen: (previous, current) {
          // Boot redirect owns the first session-restore success.
          if (!_bootCompleted || !authProvider.hasRestoredSession) {
            return false;
          }
          // Only react to success transitions (login / logout).
          return previous.state != current.state && current.isSuccess;
        },
        onError: (context, error, message) {
          if (!_bootCompleted) return;
          if (error is AuthErrorState) {
            error.maybeWhen(
              invalidCredentials: () {
                AppOverlay.showToast(
                  content: context.l10nAuth.invalid_credentials,
                );
              },
              userNotFound: () {
                AppOverlay.showToast(content: context.l10nAuth.user_not_found);
              },
              serverError: (serverMessage, code) {
                AppOverlay.showToast(content: serverMessage);
              },
              orElse: () {
                AppOverlay.showToast(
                  content: context.l10nAuth.something_went_wrong,
                );
              },
            );
          } else {
            AppOverlay.showToast(
              content: context.l10nAuth.something_went_wrong,
            );
          }
        },
        onSuccess: (context, data) {
          if (data == null) {
            getItOrNull<AuthNavigator>()?.toLogin(context);
          } else {
            getItOrNull<HomeNavigator>()?.toHome(context);
          }
        },
        child: widget.child,
      ),
    );
  }
}
