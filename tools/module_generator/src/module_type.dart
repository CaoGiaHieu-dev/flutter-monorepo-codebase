enum ModuleType { feature, domain, data, core, custom }

enum StateManagementType { provider, bloc, none }

/// How a new Feature contributes routes to the host [AppRouter].
enum FeatureRouteContribution {
  /// Standalone / stack routes via [IFeatureRouteModule] (auth, onboarding, …).
  featureRoute,

  /// Bottom-nav tab via [IDashboardTabModule] (home, settings, …).
  dashboardTab,

  /// No route DI stub (rare).
  none,
}

class ModuleConfig {
  final ModuleType type;
  final String typeDir;
  final String typeName;
  final String nameInput;
  final StateManagementType smType;
  final FeatureRouteContribution routeContribution;
  final String moduleName;
  final String modulePath;

  ModuleConfig({
    required this.type,
    required this.typeDir,
    required this.typeName,
    required this.nameInput,
    required this.smType,
    this.routeContribution = FeatureRouteContribution.featureRoute,
    required this.moduleName,
    required this.modulePath,
  });
}
