import 'package:bloc_state_management/di/module.module.dart';
import 'package:core_base_ui/di/module.module.dart';
import 'package:core_common/core_common.dart';
import 'package:core_database/di/module.module.dart';
import 'package:core_di/di/module.module.dart';
import 'package:core_network/di/module.module.dart';
import 'package:core_notifications/di/module.module.dart';
import 'package:core_storage/di/module.module.dart';
import 'package:data_auth/di/module.module.dart';
import 'package:data_core/di/module.module.dart';
import 'package:data_language/di/module.module.dart';
import 'package:domain_auth/di/module.module.dart';
import 'package:domain_core/di/module.module.dart';
import 'package:domain_language/di/module.module.dart';
import 'package:feature_auth/di/module.module.dart';
import 'package:feature_dashboard/di/module.module.dart';
import 'package:feature_home/di/module.module.dart';
import 'package:feature_onboarding/di/module.module.dart';
import 'package:feature_settings/di/module.module.dart';
import 'package:feature_splash/di/module.module.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/di/module.module.dart';

import 'injection.config.dart';

const _coreModules = [
  ExternalModule(CoreCommonPackageModule),
  ExternalModule(CoreNetworkPackageModule),
  ExternalModule(CoreNotificationsPackageModule),
  ExternalModule(CoreStoragePackageModule),
  // Registers nothing: `core_database` is mechanism only and owns no database.
  // Each package that persists data declares its own (see `data_core`).
  ExternalModule(CoreDatabasePackageModule),
  ExternalModule(CoreDiPackageModule),
];

// CoreBaseUiPackageModule depends on ILanguageStorage and IThemeStorage,
// which are app-local singletons registered before externalPackageModulesAfter.
// It must run AFTER those local bindings, so it lives here instead of _coreModules.
const _uiModules = [ExternalModule(CoreBaseUiPackageModule)];

const _domainModules = [
  ExternalModule(DomainCorePackageModule),
  ExternalModule(DomainAuthPackageModule),
  ExternalModule(DomainLanguagePackageModule),
];

const _dataModules = [
  ExternalModule(DataCorePackageModule),
  ExternalModule(DataAuthPackageModule),
  ExternalModule(DataLanguagePackageModule),
];

/// Feature modules the app assembles.
///
/// These imports are the app shell's **only intentional hard reference** to
/// feature packages: as the composition root it must name what it composes.
///
/// To drop a feature, remove in this order:
///   1. its `ExternalModule(...)` entry below and the matching import above;
///   2. its `feature_x:` entry in `app/pubspec.yaml`;
///   3. its path in the root `pubspec.yaml` `workspace:` list;
///   4. `flutter pub get` + `dart run build_runner build -d --workspace`.
///
/// Everything the shell consumes at runtime resolves through `core_di`
/// contracts with `getAllOrEmpty` / `getItOrNull` fallbacks, so no other file
/// needs editing — except the ones still holding a direct `feature_auth` /
/// `feature_splash` / `feature_shared` import (see their doc comments).
const _featureModules = [
  ExternalModule(FeatureAuthPackageModule),
  ExternalModule(FeatureDashboardPackageModule),
  ExternalModule(FeatureHomePackageModule),
  ExternalModule(FeatureOnboardingPackageModule),
  ExternalModule(FeatureSettingsPackageModule),
  ExternalModule(FeatureSplashPackageModule),
];

const _otherModules = [
  ExternalModule(ProviderStateManagementPackageModule),
  ExternalModule(BlocStateManagementPackageModule),
];

/// Configure dependency injection.
///
/// ## Ordering rule for databases
///
/// A module that opens a database with `@preResolve` runs its collected
/// `IDatabaseMigration` steps *during its own initialisation*, so any package
/// contributing a step must be registered before it. `data_core` opens
/// `CacheDatabase` here, which means a migration contributed by a **feature**
/// would not be seen — features initialise after `_dataModules`.
///
/// Nothing in the template hits this yet (no feature contributes a schema
/// step). When one does, move that feature's module ahead of the module that
/// owns the database, or give the feature its own database instead.
@InjectableInit(
  externalPackageModulesBefore: [..._coreModules],
  externalPackageModulesAfter: [
    ..._uiModules,
    ..._domainModules,
    ..._dataModules,
    ..._featureModules,
    ..._otherModules,
  ],
)
Future<void> configureDependencies({String? environment}) async {
  getIt.enableRegisteringMultipleInstancesOfOneType();
  final env = environment ?? AppConfig.appFlavor.toValue();
  await getIt.init(environment: env);
}

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  await getIt.reset();
}
