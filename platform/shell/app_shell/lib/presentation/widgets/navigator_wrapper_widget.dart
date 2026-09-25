import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_ui_kit/dialogs/app_overlay.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import '../navigation/app_router.dart';
import '../providers/deeplink_provider.dart';

/// App shell chrome wrapped around every routed page.
///
/// Owns the cold-start redirect (entry location → sign-in location →
/// post-sign-in location) and reacts to later sign-in / sign-out.
///
/// Everything module-specific arrives through product-neutral `core_di`
/// contracts resolved with `getItOrNull` — [ISessionState] for the session,
/// [ISignInLocation] / [IPostSignInLocation] for where each case lands — so
/// this file imports no module package and names no product flow (no auth,
/// no home). With no session owner in the build [ISessionState] resolves to
/// `null`, the shell treats the app as signed out, and boot falls through to
/// the registered entry location instead of throwing.
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
  final _session = getItOrNull<ISessionState>();
  final deeplinkProvider = getIt<DeeplinkProvider>();

  StreamSubscription<SessionPrincipal?>? _sessionSubscription;
  StreamSubscription<SessionFailure>? _failureSubscription;

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
        // With a session owner, leaving onboarding leads to a sign-in, and
        // `_onSessionChanged` → `_goToPostSignIn` starts deep links. Without
        // one no sign-in ever comes, so start them once the user leaves the
        // entry location instead — still never over onboarding itself.
        if (_session == null) _startDeepLinksOnLeavingEntry();
        return;
      }

      final isGoToSignIn = _goToSignIn();
      if (isGoToSignIn) {
        _bootCompleted = true;
        return;
      }

      _goToPostSignIn();
      _bootCompleted = true;
    });
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _failureSubscription?.cancel();
    _stopWatchingEntryExit();
    super.dispose();
  }

  GoRouter? _watchedRouter;
  VoidCallback? _entryExitListener;

  /// Calls [DeeplinkProvider.initAppLink] the first time the router leaves
  /// the location it is on now (the entry location).
  void _startDeepLinksOnLeavingEntry() {
    final router = GoRouter.of(context);
    final entryPath = router.routerDelegate.currentConfiguration.uri.path;

    void listener() {
      if (router.routerDelegate.currentConfiguration.uri.path == entryPath) {
        return;
      }
      _stopWatchingEntryExit();
      deeplinkProvider.initAppLink();
    }

    _watchedRouter = router;
    _entryExitListener = listener;
    router.routerDelegate.addListener(listener);
  }

  void _stopWatchingEntryExit() {
    final listener = _entryExitListener;
    if (listener != null) {
      _watchedRouter?.routerDelegate.removeListener(listener);
    }
    _watchedRouter = null;
    _entryExitListener = null;
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
  /// `getItOrNull`: [ISignInLocation] is contributed by whichever module owns
  /// sign-in (`feature_auth` in the samples). If none is part of the build
  /// boot must fall through to the next destination instead of throwing —
  /// matching [_onSessionChanged] below, which resolves it optionally too.
  bool _goToSignIn() {
    if (_session?.signedInUser != null) return false;

    final signIn = getItOrNull<ISignInLocation>();
    if (signIn == null) return false;

    context.go(signIn.path);
    return true;
  }

  /// Goes to the registered [IPostSignInLocation] (the home tab in the
  /// samples), otherwise to [AppRouter.fallbackLocation].
  ///
  /// The fallback used to be implicit — "the router's initial location
  /// decides" — which only holds at boot. After a sign-in nothing navigated
  /// at all, so a build without a landing module left a signed-in user on the
  /// sign-in screen.
  ///
  /// Also starts deep-link routing — here rather than only at boot, so a user
  /// who started signed out gets it after signing in. `initAppLink` is
  /// idempotent.
  void _goToPostSignIn() {
    deeplinkProvider.initAppLink();
    context.go(
      getItOrNull<IPostSignInLocation>()?.path ??
          getIt<AppRouter>().fallbackLocation,
    );
  }

  /// Routes on settled session transitions (sign-in / sign-out).
  ///
  /// Ignored until the boot redirect has run and the first session restore has
  /// finished — otherwise the restore's own emission would navigate a second
  /// time, on top of the destination boot just chose.
  void _onSessionChanged(SessionPrincipal? user) {
    if (!mounted || !_bootCompleted) return;
    if (!(_session?.hasRestoredSession ?? false)) return;

    if (user == null) {
      final signIn = getItOrNull<ISignInLocation>();
      if (signIn != null) context.go(signIn.path);
    } else {
      _goToPostSignIn();
    }
  }

  /// Surfaces a failed session operation as a toast.
  ///
  /// Strings come from `core_base_ui`'s global translations rather than a
  /// module's, so the shell stays translatable with no module present.
  void _onSessionFailure(SessionFailure failure) {
    if (!mounted || !_bootCompleted) return;

    final l10n = context.l10n;
    final content = switch (failure) {
      SessionInvalidCredentialsFailure() => l10n.invalidCredentials,
      SessionUserNotFoundFailure() => l10n.userNotFound,
      SessionServerFailure(:final message) => message,
      SessionUnknownFailure() => l10n.somethingWentWrong,
    };

    AppOverlay.showToast(content: content);
  }

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(child: widget.child);
  }
}
