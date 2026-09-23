// composer:managed:imports — generated from app_manifest.yaml
import 'package:bloc_state_management/di/module.module.dart';
import 'package:core_base_ui/di/module.module.dart';
import 'package:core_common/core_common.dart';
import 'package:core_common/di/module.module.dart';
import 'package:core_database/di/module.module.dart';
import 'package:core_di/di/module.module.dart';
import 'package:core_network/di/module.module.dart';
import 'package:core_notifications/di/module.module.dart';
import 'package:core_storage/di/module.module.dart';
import 'package:data_auth/di/module.module.dart';
import 'package:data_core/di/module.module.dart';
import 'package:domain_auth/di/module.module.dart';
import 'package:domain_core/di/module.module.dart';
import 'package:feature_auth/di/module.module.dart';
import 'package:feature_dashboard/di/module.module.dart';
import 'package:feature_home/di/module.module.dart';
import 'package:feature_onboarding/di/module.module.dart';
import 'package:feature_settings/di/module.module.dart';
import 'package:feature_splash/di/module.module.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_app_shell/di/module.module.dart';
import 'package:provider_state_management/di/module.module.dart';

import 'injection.config.dart';
// composer:end:imports

/// Dependency injection for the `mobile` app.
///
/// **The module lists below are generated.** They are derived from
/// `apps/mobile/app_manifest.yaml` by:
///
/// ```bash
/// dart tools/composer/composer.dart sync --app mobile
/// ```
///
/// Adding or removing a module used to mean editing this file, `apps/mobile/pubspec.yaml`
/// and the root `workspace:` list by hand, keeping all three in step. Getting it
/// wrong fails at boot with `"<Type> is not registered"` — which `flutter
/// analyze` cannot see. Edit the manifest instead; `composer verify` fails CI if
/// this file has drifted from it.
///
/// Group order is load-bearing and is declared in the manifest's `di_groups`:
/// `configureDependencies()` initialises modules in exactly that sequence, and
/// an eager `@Singleton` may only depend on a type registered by an earlier
/// group (AGENTS.md §18).

// composer:managed:modules — generated from app_manifest.yaml
const _coreModules = [
  ExternalModule(CoreCommonPackageModule),
  ExternalModule(CoreNetworkPackageModule),
  ExternalModule(CoreStoragePackageModule),
  ExternalModule(CoreDatabasePackageModule),
  ExternalModule(CoreDiPackageModule),
];

const _notificationsModules = [
  ExternalModule(CoreNotificationsPackageModule),
];

const _shellModules = [
  ExternalModule(PlatformAppShellPackageModule),
];

const _uiModules = [
  ExternalModule(CoreBaseUiPackageModule),
];

const _domainModules = [
  ExternalModule(DomainCorePackageModule),
  ExternalModule(DomainAuthPackageModule),
];

const _dataModules = [
  ExternalModule(DataCorePackageModule),
  ExternalModule(DataAuthPackageModule),
];

const _featureModules = [
  ExternalModule(FeatureAuthPackageModule),
  ExternalModule(FeatureHomePackageModule),
  ExternalModule(FeatureSettingsPackageModule),
  ExternalModule(FeatureOnboardingPackageModule),
  ExternalModule(FeatureSplashPackageModule),
  ExternalModule(FeatureDashboardPackageModule),
];

const _otherModules = [
  ExternalModule(ProviderStateManagementPackageModule),
  ExternalModule(BlocStateManagementPackageModule),
];

const _externalModulesBefore = [..._coreModules];
const _externalModulesAfter = [
    ..._notificationsModules,
    ..._shellModules,
    ..._uiModules,
    ..._domainModules,
    ..._dataModules,
    ..._featureModules,
    ..._otherModules,
];
// composer:end:modules

@InjectableInit(
  externalPackageModulesBefore: _externalModulesBefore,
  externalPackageModulesAfter: _externalModulesAfter,
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
