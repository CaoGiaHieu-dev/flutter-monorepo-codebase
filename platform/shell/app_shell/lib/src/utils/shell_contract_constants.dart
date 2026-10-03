import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import '../composition/shell_contracts.dart';
import '../navigation/app_router.dart';
import '../provider/deeplink_provider.dart';

/// What the shell resolves from dependency injection — 7 required rows the
/// shell's own packages register and 14 optional rows an app or a module
/// contributes.
///
/// `ISessionStatusStream` is not here: only `feature_home` looks it up, and a
/// module's own lookups are its business, not the shell's.
const List<ShellContract<Object>> SHELL_CONTRACTS = [
  ShellContract<ILanguageStorage>(
    id: 'language_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/ui/design_system/lib/src/language/language_provider.dart:19, '
        'platform/shell/adapters/lib/src/network_config_impl.dart:42',
    whenAbsent: 'boot throws "ILanguageStorage is not registered"',
  ),
  ShellContract<IThemeStorage>(
    id: 'theme_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/ui/design_system/lib/src/theme/theme_provider.dart:26',
    whenAbsent: 'boot throws "IThemeStorage is not registered"',
  ),
  ShellContract<AppBootStorage>(
    id: 'boot_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/navigation/app_router.dart:133, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:139',
    whenAbsent: 'the first-launch rule cannot run',
  ),
  ShellContract<AppRouter>(
    id: 'app_router',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/root_app.dart:54, '
        'platform/shell/app_shell/lib/src/bootstrap.dart:191',
    whenAbsent: 'boot throws "AppRouter is not registered"',
  ),
  ShellContract<DeeplinkProvider>(
    id: 'deeplink_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/app_material_wrapper.dart:122, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:41',
    whenAbsent: 'boot throws "DeeplinkProvider is not registered"',
  ),
  ShellContract<ThemeProvider>(
    id: 'theme_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:110',
    whenAbsent: 'boot throws "ThemeProvider is not registered"',
  ),
  ShellContract<LanguageProvider>(
    id: 'language_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:111',
    whenAbsent: 'boot throws "LanguageProvider is not registered"',
  ),
  ShellContract<ISessionState>(
    id: 'session_state',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:40, '
        'platform/shell/app_shell/lib/src/provider/deeplink_provider.dart:75, '
        'platform/shell/adapters/lib/src/network_config_impl.dart:95',
    whenAbsent:
        'the navigation wrapper treats the app as signed out, every deep '
        'link is routed, and a lost session is a no-op',
  ),
  ShellContract<ISessionGateway>(
    id: 'session_gateway',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/adapters/lib/src/network_config_impl.dart:46',
    whenAbsent: 'requests carry no bearer token and nothing refreshes it',
  ),
  ShellContract<ISessionRefreshListenable>(
    id: 'session_refresh',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:169',
    whenAbsent: 'the router never re-resolves its location on a session change',
  ),
  ShellContract<ISignInLocation>(
    id: 'sign_in',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:157, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:193',
    whenAbsent: 'the shell never redirects a signed-out user',
  ),
  ShellContract<IFeatureRouteModule>(
    id: 'routes',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:66',
    whenAbsent: 'the router has no stack routes',
  ),
  ShellContract<INavDestinationModule>(
    id: 'tabs',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:59',
    whenAbsent: 'the router opens one placeholder route (`/_empty_dashboard`)',
  ),
  ShellContract<IDashboardRouteModule>(
    id: 'dashboard',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:191',
    whenAbsent: 'the destinations render without any chrome',
  ),
  ShellContract<IAppEntryLocation>(
    id: 'entry',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/navigation/app_router.dart:127, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:136',
    whenAbsent:
        'there is no first-launch entry; boot goes to the sign-in check',
  ),
  ShellContract<IPostSignInLocation>(
    id: 'post_sign_in',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:178',
    whenAbsent: 'after sign-in the router opens its fallback, the first tab',
  ),
  ShellContract<IAppSplashScreen>(
    id: 'splash',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart:185',
    whenAbsent: 'the native splash is kept through boot',
  ),
  ShellContract<IAppTreeWrapper>(
    id: 'tree_wrappers',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:96',
    whenAbsent: 'the widget tree is built unwrapped',
  ),
  ShellContract<IFeatureLocalization>(
    id: 'localization',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:158',
    whenAbsent: 'only core_base_ui\'s own strings are translated',
  ),
  ShellContract<IErrorReporter>(
    id: 'error_reporter',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart:435',
    whenAbsent: 'errors are printed and sent nowhere (RULE-67)',
  ),
  ShellContract<IAnalytics>(
    id: 'analytics',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/foundation/common/lib/src/go_route_data_custom.dart:103',
    whenAbsent: 'no screen events are sent',
  ),
];
