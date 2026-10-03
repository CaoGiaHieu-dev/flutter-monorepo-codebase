/// Whether, and when, the app opens on the entry location a module
/// contributes (`IAppEntryLocation` — onboarding in the samples).
enum EntryPolicy {
  /// On the first launch only; later cold starts open the fallback location.
  firstLaunch,

  /// On every cold start. The boot redirect still moves a returning user on.
  always,

  /// Never: a registered entry location is ignored.
  never,
}

/// Where the router starts and where it falls back to.
///
/// Defaults are what the shell did before an app could say anything: the entry
/// location on the first launch, the first tab as the fallback.
final class RouterProfile {
  const RouterProfile({
    this.entry = EntryPolicy.firstLaunch,
    this.fallbackPath,
  });

  /// When the entry location is used. Default [EntryPolicy.firstLaunch].
  final EntryPolicy entry;

  /// The app's home: where a signed-in user lands when no module says
  /// otherwise, and where "go home" goes. It must be a route the app
  /// registers. Null (the default) is the first destination, else the
  /// placeholder `/_empty_dashboard`.
  final String? fallbackPath;
}
