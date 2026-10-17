import 'package:go_router/go_router.dart';

/// Top-level feature routes nested under the app [ShellRoute]
/// (e.g. onboarding, auth) — not dashboard tabs.
///
/// Register via DI; the app shell expands `getAllOrEmpty<IFeatureRouteModule>()`.
/// Sibling route order does not matter when paths are distinct (GoRouter matches
/// by path). Prefer unique paths; avoid overlapping catch-alls across modules.
///
/// The shared navigator keys these routes attach to live in
/// `navigator_keys.dart`.
abstract class IFeatureRouteModule {
  List<RouteBase> get routes;
}
