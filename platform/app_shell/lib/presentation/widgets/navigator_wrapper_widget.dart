import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/di/module.dart';
import 'package:core_di/core_di.dart';
import 'package:core_ui_kit/dialogs/app_overlay.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../di/app_boot_storage.dart';
import '../navigation/app_router.dart';
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
/// (`core_ui_kit` is still imported for [AppOverlay]; it lives under
/// `platform/` because it is a shared UI library, not a removable
/// feature.)
class NavigatorWrapperWidget extends StatefulWidget {
  final Widget child;

  const NavigatorWrapperWidget({required this.child});

  @override
  State<NavigatorWrapperWidget> createState() => NavigatorWrapperWidgetState();
}

class NavigatorWrapperWidgetState extends State<NavigatorWrapperWidget> {
  final _session = getItOrNull<IAuthSessionState>();
  final deeplinkProvider = getIt<DeeplinkProvider>();

  StreamSubscription<AuthPrincipal?>? _sessionSubscription;
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
      _bootCompleted = true;
    });
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _failureSubscription?.cancel();
    super.dispose();
  }

  /// Returns `true` when first launch should stay on the entry location.
  ///
  /// That only makes sense when a module actually contributed one. This used
  /// to return `true` on every first launch regardless, relying on
  /// `initialLocation` being the onboarding screen — so in any build without
  /// an onboarding module the router started on its fallback (the first tab),
  /// this returned early, and the login redirect below never ran. The very
  /// first launch of such an app opened signed-out on a protected screen.
  bool _goToOnboarding() {
    if (getItOrNull<IAppEntryLocation>() == null) return false;
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

  /// Goes to the home module when one is composed, otherwise to
  /// [AppRouter.fallbackLocation].
  ///
  /// The fallback used to be implicit — "the router's initial location
  /// decides" — which only holds at boot. After a sign-in nothing navigated
  /// at all, so a build without `feature_home` left a signed-in user on the
  /// login screen.
  ///
  /// Also starts deep-link routing — here rather than only at boot, so a user
  /// who started signed out gets it after signing in. `initAppLink` is
  /// idempotent.
  void _goToHome() {
    deeplinkProvider.initAppLink();
    final home = getItOrNull<HomeNavigator>();
    if (home != null) {
      home.toHome(context);
      return;
    }
    context.go(getIt<AppRouter>().fallbackLocation);
  }

  /// Routes on settled session transitions (sign-in / sign-out).
  ///
  /// Ignored until the boot redirect has run and the first session restore has
  /// finished — otherwise the restore's own emission would navigate a second
  /// time, on top of the destination boot just chose.
  void _onSessionChanged(AuthPrincipal? user) {
    if (!mounted || !_bootCompleted) return;
    if (!(_session?.hasRestoredSession ?? false)) return;

    if (user == null) {
      getItOrNull<AuthNavigator>()?.toLogin(context);
    } else {
      _goToHome();
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
      AuthInvalidCredentialsFailure() => l10n.invalidCredentials,
      AuthUserNotFoundFailure() => l10n.userNotFound,
      AuthServerFailure(:final message) => message,
      AuthUnknownFailure() => l10n.somethingWentWrong,
    };

    AppOverlay.showToast(content: content);
  }

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(child: widget.child);
  }
}
