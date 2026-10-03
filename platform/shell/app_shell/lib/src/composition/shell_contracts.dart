import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import '../navigation/app_router.dart';
import '../provider/deeplink_provider.dart';

/// Whether the shell can run without a contract.
enum ShellNeed {
  /// The shell registers it itself, from its own packages. Without it the
  /// shell does not work.
  required,

  /// An app or a module contributes it. Without it the shell degrades as the
  /// row's `whenAbsent` says — and the app declares which it chose.
  optional,
}

/// How many implementations the shell collects of a contract.
enum ContractCardinality {
  /// One, resolved with `getItOrNull`.
  one,

  /// Any number, collected with `getAllOrEmpty`.
  many,
}

/// One thing the shell resolves from dependency injection: what it is, what
/// the shell does without it, and where it is looked up.
///
/// The catalog ([kShellContracts]) is the one table of what an app must and
/// may provide. `checkAppContract` holds every app to it, and each lookup
/// stays `getItOrNull` / `getAllOrEmpty` with a fallback (RULE-12), so an app
/// composed without a contributing module still boots.
final class ShellContract<T extends Object> {
  const ShellContract({
    required this.id,
    required this.need,
    required this.cardinality,
    required this.consumer,
    required this.whenAbsent,
    this.bundle,
  });

  /// The stable id an app's `capabilities:` declaration uses (`splash`,
  /// `session_state`).
  final String id;

  /// Whether the shell needs it, or an app may go without.
  final ShellNeed need;

  /// How many implementations the shell collects.
  final ContractCardinality cardinality;

  /// The manifest key that declares this contract together with its
  /// siblings — a bundle declares all its members at once (`session`) — or
  /// `null` when the contract is declared under its own [id].
  final String? bundle;

  /// Where the shell looks it up: `path:line`, comma-separated when there are
  /// several. Shown in the app report; a test holds each line to the contract
  /// it names.
  final String consumer;

  /// What the shell does when nothing is registered, in a sentence — shown
  /// verbatim in the app report and in the problems that name this contract.
  final String whenAbsent;

  /// The contract's type.
  Type get type => T;

  /// The manifest key that declares this contract: its [bundle], else its
  /// [id].
  String get manifestKey => bundle ?? id;

  /// What the graph has registered for [T] right now, resolved the way the
  /// shell resolves it — never `getIt` / `getAll`, so an absent registration
  /// is an empty list.
  List<Object> registered() => cardinality == ContractCardinality.many
      ? [...getAllOrEmpty<T>()]
      : [?getItOrNull<T>()];
}

/// What the shell resolves from dependency injection — 8 required rows the
/// shell's own packages register and 14 optional rows an app or a module
/// contributes.
///
/// `ISessionStatusStream` is not here: only `feature_home` looks it up, and a
/// module's own lookups are its business, not the shell's.
const List<ShellContract<Object>> kShellContracts = [
  ShellContract<ILanguageStorage>(
    id: 'language_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/ui/design_system/lib/src/language/language_provider.dart:15, '
        'platform/shell/adapters/lib/src/network_config_impl.dart:35',
    whenAbsent: 'boot throws "ILanguageStorage is not registered"',
  ),
  ShellContract<IThemeStorage>(
    id: 'theme_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/ui/design_system/lib/src/theme/theme_provider.dart:25',
    whenAbsent: 'boot throws "IThemeStorage is not registered"',
  ),
  ShellContract<AppBootStorage>(
    id: 'boot_storage',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/navigation/app_router.dart:110, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:136',
    whenAbsent: 'the first-launch rule cannot run',
  ),
  ShellContract<SslPinningConfig>(
    id: 'ssl_pinning',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/foundation/common/lib/src/config/app_initializer.dart:156',
    whenAbsent:
        'certificate pinning is skipped and an ERROR is logged; it must be '
        'bound in its own right, never as a supertype (RULE-14)',
  ),
  ShellContract<AppRouter>(
    id: 'app_router',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/root_app.dart:48, '
        'platform/shell/app_shell/lib/src/bootstrap.dart:202',
    whenAbsent: 'boot throws "AppRouter is not registered"',
  ),
  ShellContract<DeeplinkProvider>(
    id: 'deeplink_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/app_material_wrapper.dart:110, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:41',
    whenAbsent: 'boot throws "DeeplinkProvider is not registered"',
  ),
  ShellContract<ThemeProvider>(
    id: 'theme_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:98',
    whenAbsent: 'boot throws "ThemeProvider is not registered"',
  ),
  ShellContract<LanguageProvider>(
    id: 'language_provider',
    need: ShellNeed.required,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:99',
    whenAbsent: 'boot throws "LanguageProvider is not registered"',
  ),
  ShellContract<ISessionState>(
    id: 'session_state',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:40, '
        'platform/shell/app_shell/lib/src/provider/deeplink_provider.dart:46, '
        'platform/shell/adapters/lib/src/network_config_impl.dart:87',
    whenAbsent:
        'the navigation wrapper treats the app as signed out, every deep '
        'link is routed, and a lost session is a no-op',
  ),
  ShellContract<ISessionGateway>(
    id: 'session_gateway',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/adapters/lib/src/network_config_impl.dart:38',
    whenAbsent: 'requests carry no bearer token and nothing refreshes it',
  ),
  ShellContract<ISessionRefreshListenable>(
    id: 'session_refresh',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:139',
    whenAbsent: 'the router never re-resolves its location on a session change',
  ),
  ShellContract<ISignInLocation>(
    id: 'sign_in',
    bundle: 'session',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:154, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:190',
    whenAbsent: 'the shell never redirects a signed-out user',
  ),
  ShellContract<IFeatureRouteModule>(
    id: 'routes',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:51',
    whenAbsent: 'the router has no stack routes',
  ),
  ShellContract<INavDestinationModule>(
    id: 'tabs',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:45',
    whenAbsent: 'the router opens one placeholder route (`/_empty_dashboard`)',
  ),
  ShellContract<IDashboardRouteModule>(
    id: 'dashboard',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/navigation/app_router.dart:161',
    whenAbsent: 'the destinations render without any chrome',
  ),
  ShellContract<IAppEntryLocation>(
    id: 'entry',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer:
        'platform/shell/app_shell/lib/src/navigation/app_router.dart:105, '
        'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:133',
    whenAbsent:
        'there is no first-launch entry; boot goes to the sign-in check',
  ),
  ShellContract<IPostSignInLocation>(
    id: 'post_sign_in',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/widgets/navigator_wrapper_widget.dart:175',
    whenAbsent: 'after sign-in the router opens its fallback, the first tab',
  ),
  ShellContract<IAppSplashScreen>(
    id: 'splash',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart:197',
    whenAbsent: 'the native splash is kept through boot',
  ),
  ShellContract<IAppTreeWrapper>(
    id: 'tree_wrappers',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:84',
    whenAbsent: 'the widget tree is built unwrapped',
  ),
  ShellContract<IFeatureLocalization>(
    id: 'localization',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.many,
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart:142',
    whenAbsent: 'only core_base_ui\'s own strings are translated',
  ),
  ShellContract<IErrorReporter>(
    id: 'error_reporter',
    need: ShellNeed.optional,
    cardinality: ContractCardinality.one,
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart:345',
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
