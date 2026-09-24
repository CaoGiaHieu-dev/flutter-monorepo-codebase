/// Where the app shell sends a user once a session exists.
///
/// Used on a cold start with a restored session and after every sign-in. A
/// plain [path], like [IAppEntryLocation] and [ISignInLocation], so the
/// contract stays router-neutral. It replaces the shell's use of
/// `HomeNavigator`, which tied the platform to one product module.
///
/// Contributed by the module that owns the landing screen (the `home`
/// sample's `HomePostSignInLocation`). Resolve it with `getItOrNull`: with
/// none registered the shell goes to `AppRouter.fallbackLocation` — the first
/// navigation destination, else an empty placeholder route.
abstract class IPostSignInLocation {
  String get path;
}
