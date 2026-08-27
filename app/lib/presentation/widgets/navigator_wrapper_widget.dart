import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/di/module.dart';
import 'package:core_di/core_di.dart';
import 'package:core_ui_kit/dialogs/app_overlay.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:flutter/material.dart';

import '../../di/app_boot_storage.dart';
import '../providers/deeplink_provider.dart';

/// App shell chrome wrapped around every routed page.
///
/// Owns the cold-start redirect (onboarding → login → home) and reacts to
/// later sign-in / sign-out.
///
/// Everything feature-specific arrives through `core_di` contracts resolved
/// with `getItOrNull`, so this file imports no feature package. With no auth
/// feature in the build [IAuthSessionState] resolves to `null`, the shell
/// treats the app as signed out, and boot falls through to the registered
/// entry location instead of throwing.
///
/// (`feature_shared` is still imported for [AppOverlay]; it is a shared UI
/// library rather than a removable feature.)
class NavigatorWrapperWidget extends StatefulWidget {
  final Widget child;

  const NavigatorWrapperWidget({required this.child});

  @override
  State<NavigatorWrapperWidget> createState() => NavigatorWrapperWidgetState();
}

class NavigatorWrapperWidgetState extends State<NavigatorWrapperWidget> {
  final _session = getItOrNull<IAuthSessionState>();
  final deeplinkProvider = getIt<DeeplinkProvider>();

  StreamSubscription<UserEntity?>? _sessionSubscription;
  StreamSubscription<AuthSessionFailure>? _failureSubscription;

  /// Boot redirect owns the first navigation. The listeners below handle later
  /// sign-in / sign-out transitions only.
  bool _bootCompleted = false;

  @override
  void initState() {
    super.initState();

    // Subscribe before the first frame so no transition is missed; the
    // `_bootCompleted` gate discards anything that arrives during boot.
    _sessionSubscription = _session?.sessionChanges.listen(_onSessionChanged);
    _failureSubscription = _session?.sessionFailures.listen(_onSessionFailure);

    WidgetsBinding.instance.endOfFrame.whenComplete(() async {
      await _session?.ensureInitialized();
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

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _failureSubscription?.cancel();
    super.dispose();
  }

  bool _goToOnboarding() {
    try {
      if (_session?.signedInUser != null) {
        return false;
      }
      final viewed = getIt<AppBootStorage>().viewedOnboard.value ?? false;
      return !viewed;
    } finally {
      getIt<AppBootStorage>().viewedOnboard.value = true;
    }
  }

  /// Returns `true` only when it actually navigated, so the caller can stop.
  ///
  /// `getItOrNull`: `AuthNavigator` is owned by `feature_auth`. If that package
  /// is not part of the build the navigator is unregistered, and boot must fall
  /// through to the next destination instead of throwing — matching
  /// [_onSessionChanged] below, which resolves it optionally too.
  bool _goToLogin() {
    if (_session?.signedInUser != null) return false;

    final navigator = getItOrNull<AuthNavigator>();
    if (navigator == null) return false;

    navigator.toLogin(context);
    return true;
  }

  /// No-op when `feature_home` is absent; the router's fallback location
  /// (`AppRouter._fallbackLocation`) then decides where the app lands.
  void _goToHome() {
    getItOrNull<HomeNavigator>()?.toHome(context);
  }

  /// Routes on settled session transitions (sign-in / sign-out).
  ///
  /// Ignored until the boot redirect has run and the first session restore has
  /// finished — otherwise the restore's own emission would navigate a second
  /// time, on top of the destination boot just chose.
  void _onSessionChanged(UserEntity? user) {
    if (!mounted || !_bootCompleted) return;
    if (!(_session?.hasRestoredSession ?? false)) return;

    if (user == null) {
      getItOrNull<AuthNavigator>()?.toLogin(context);
    } else {
      getItOrNull<HomeNavigator>()?.toHome(context);
    }
  }

  /// Surfaces a failed session operation as a toast.
  ///
  /// Strings come from `core_base_ui`'s global translations rather than a
  /// feature's, so the shell stays translatable with no feature present.
  void _onSessionFailure(AuthSessionFailure failure) {
    if (!mounted || !_bootCompleted) return;

    final l10n = context.l10n;
    final content = switch (failure) {
      AuthInvalidCredentialsFailure() => l10n.invalid_credentials,
      AuthUserNotFoundFailure() => l10n.user_not_found,
      AuthServerFailure(:final message) => message,
      AuthUnknownFailure() => l10n.something_went_wrong,
    };

    AppOverlay.showToast(content: content);
  }

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(child: widget.child);
  }
}
