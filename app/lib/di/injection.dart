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

/// Configure dependency injection
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
