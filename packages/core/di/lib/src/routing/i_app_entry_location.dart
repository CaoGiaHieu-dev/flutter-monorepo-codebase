/// Optional cold-start location for [GoRouter.initialLocation].
///
/// Typically implemented by onboarding. If unregistered, the app shell falls
/// back to the first [INavDestinationModule.path] or `/`.
abstract class IAppEntryLocation {
  String get path;
}
