/// Optional first-launch location for [GoRouter.initialLocation].
///
/// Typically implemented by onboarding. The app shell starts the router here
/// only until it has shown it once (the shell records that in its own boot
/// storage); every later cold start — and every build that registers none —
/// starts at the shell's fallback: the first [INavDestinationModule.path],
/// else an empty placeholder route.
abstract class IAppEntryLocation {
  String get path;
}
