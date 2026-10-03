import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';

import '../navigation/app_router.dart';
import '../utils/shell_contract_constants.dart';
import 'shell_contracts.dart';

/// Holds an app's declaration to the dependency graph it actually built:
/// the one check the DI smoke test and the debug boot share.
///
/// Call it after dependency injection. It resolves every row of
/// [SHELL_CONTRACTS] the way the shell does (`getItOrNull` /
/// `getAllOrEmpty`, so absence is data, not a throw) and compares it with
/// what `profile.facts.capabilities` declares:
///
/// - `C01` a required contract is not registered;
/// - `C02` declared `provided`, nothing registered;
/// - `C03` declared `absent`, something registered;
/// - `C04` the members of a bundle (`session`) disagree;
/// - `C05` no route and no tab: the app has no screen;
/// - `C06` two `INavDestinationModule`s share an `order` (RULE-24);
/// - `C07` `AppRouter.router` fails to assemble;
/// - `C08` `DioFailureClassifier` is not registered exactly once;
/// - `C09` an optional contract has no declaration at all;
/// - `C10` a registration's constructor throws when the contract is resolved;
/// - `C11` `RouterProfile.fallbackPath` is not a route the assembled router
///   registers;
/// - `C12` two or more navigation tabs and no `IDashboardRouteModule`: no
///   chrome to switch between them.
///
/// Resolving a contract builds its lazy registration, and the router is
/// assembled eagerly (`C07`), so this runs app code. What it throws never
/// escapes: a throwing constructor is a `C10` problem in the report, handled
/// like any other — a production release logs it and goes on (the shell would
/// meet the same error at its own first lookup, with the reason on record).
/// [flavor] and [platform] only label the report — nothing in the graph
/// differs by them.
CompositionReport checkAppContract(
  AppProfile profile, {
  required Flavor flavor,
  required AppPlatform platform,
}) {
  final id = profile.facts.id;
  final manifest = 'apps/$id/app_manifest.yaml';
  final sync = 'dart tools/composer/composer.dart sync --app $id';
  final states = <ContractState>[];
  final problems = <ProfileProblem>[];
  // Contracts whose resolution threw: reported once as `C10`, never compared
  // with the declaration, and not resolved a second time by the structure
  // checks below.
  final failed = <Type>{};

  for (final contract in SHELL_CONTRACTS) {
    final declared = contract.need == ShellNeed.optional
        ? profile.facts.capabilities[contract.id]
        : null;

    final List<Object> registered;
    try {
      registered = contract.registered();
    } catch (error) {
      failed.add(contract.type);
      states.add(
        ContractState(
          contract: contract,
          expectation: declared,
          registered: const [],
        ),
      );
      problems.add(
        ProfileProblem(
          code: 'C10',
          description:
              '`${contract.type}` (`${contract.id}`) is registered, but '
              'resolving it threw: $error',
          action:
              'Fix the constructor or the registration the error names — '
              'the shell resolves `${contract.type}` the same way and would '
              'throw the same error at its first lookup.',
        ),
      );
      continue;
    }
    states.add(
      ContractState(
        contract: contract,
        expectation: declared,
        registered: registered,
      ),
    );

    if (contract.need == ShellNeed.required) {
      if (registered.isEmpty) {
        problems.add(
          ProfileProblem(
            code: 'C01',
            description:
                '`${contract.type}` (`${contract.id}`) is required by the '
                'shell, but nothing registers it. Without it: '
                '${contract.whenAbsent}.',
            action:
                'Compose the shell package that registers it — the `shell` '
                'and `ui` groups of `di_groups:` in $manifest — and run '
                '`$sync`.',
          ),
        );
      }
      continue;
    }

    final key = contract.manifestKey;
    switch (declared) {
      case null:
        problems.add(
          ProfileProblem(
            code: 'C09',
            description:
                'The optional contract `${contract.id}` (`${contract.type}`) '
                'has no declaration in the app facts.',
            action:
                'Declare `$key` under `capabilities:` in $manifest — '
                '`$key: provided`, or `$key: { state: absent, reason: '
                '"<why>" }` — and run `$sync`.',
          ),
        );
      case ProvidedCapability():
        if (registered.isEmpty) {
          problems.add(
            ProfileProblem(
              code: 'C02',
              description:
                  '`capabilities.$key` is declared `provided` in $manifest, '
                  'but nothing registers `${contract.type}`. Without it: '
                  '${contract.whenAbsent}.',
              action:
                  'Compose the module that registers `${contract.type}`, or '
                  'declare it absent: `$key: { state: absent, reason: '
                  '"${contract.whenAbsent}" }` — then run `$sync`.',
            ),
          );
        }
      case AbsentCapability(:final reason):
        if (registered.isNotEmpty) {
          problems.add(
            ProfileProblem(
              code: 'C03',
              description:
                  '`capabilities.$key` is declared `absent` in $manifest '
                  '(reason: $reason), but `${contract.type}` is registered: '
                  '${_names(registered)}.',
              action:
                  'Declare it `$key: provided` and run `$sync`, or remove '
                  'the module or registration that adds it.',
            ),
          );
        }
    }
  }

  problems
    ..addAll(_bundleDisagreements(profile, manifest, sync))
    ..addAll(_structure(failed, profile));

  return CompositionReport(
    appId: id,
    flavor: flavor,
    platform: platform,
    states: List.unmodifiable(states),
    problems: List.unmodifiable(problems),
  );
}

/// `C04`: the declared states of one bundle's members must agree — they are
/// declared together, under the bundle's key.
Iterable<ProfileProblem> _bundleDisagreements(
  AppProfile profile,
  String manifest,
  String sync,
) sync* {
  final bundles = <String, List<ShellContract<Object>>>{};
  for (final contract in SHELL_CONTRACTS) {
    final bundle = contract.bundle;
    if (bundle != null) bundles.putIfAbsent(bundle, () => []).add(contract);
  }

  for (final MapEntry(key: bundle, value: members) in bundles.entries) {
    final states = {
      for (final member in members)
        member.id: profile.facts.capabilities[member.id],
    }..removeWhere((_, expectation) => expectation == null);
    final provided = states.values.whereType<ProvidedCapability>().length;
    if (provided == 0 || provided == states.length) continue;

    final declared = [
      for (final MapEntry(key: id, value: expectation) in states.entries)
        '$id is ${expectation is ProvidedCapability ? 'provided' : 'absent'}',
    ];
    yield ProfileProblem(
      code: 'C04',
      description:
          'The members of the `$bundle` bundle disagree in the app facts: '
          '${declared.join(', ')}.',
      action:
          'Declare the bundle once in $manifest — `$bundle: provided`, or '
          '`$bundle: { state: absent, reason: "<why>" }` — and run `$sync`.',
    );
  }
}

/// `C05`–`C08` and `C11`: what both smoke tests used to check by hand. A
/// contract in [failed] already threw while it was resolved (`C10`): what
/// depends on it is skipped rather than reported twice.
Iterable<ProfileProblem> _structure(
  Set<Type> failed,
  AppProfile profile,
) sync* {
  final routes = failed.contains(IFeatureRouteModule)
      ? null
      : getAllOrEmpty<IFeatureRouteModule>().toList();
  final tabs = failed.contains(INavDestinationModule)
      ? null
      : getAllOrEmpty<INavDestinationModule>().toList();

  if (routes != null && tabs != null && routes.isEmpty && tabs.isEmpty) {
    yield const ProfileProblem(
      code: 'C05',
      description:
          'The app has no route module and no navigation tab, so it has no '
          'screen to show.',
      action:
          'Compose a feature that contributes an `IFeatureRouteModule` or an '
          '`INavDestinationModule` (RULE-20).',
    );
  }

  if (tabs != null &&
      tabs.length >= 2 &&
      !failed.contains(IDashboardRouteModule) &&
      getItOrNull<IDashboardRouteModule>() == null) {
    yield ProfileProblem(
      code: 'C12',
      description:
          'The app composes ${tabs.length} navigation tabs '
          '(${_names(tabs)}) and no `IDashboardRouteModule`. Without a '
          'dashboard the destinations render with no navigation chrome, so '
          'every tab after the first is unreachable from the UI.',
      action:
          'Compose the module that registers `IDashboardRouteModule` (the '
          'sample is `feature_dashboard`) and declare `dashboard: provided`, '
          'or compose one tab only — then run '
          '`dart tools/composer/composer.dart sync --app ${profile.facts.id}`.',
    );
  }

  final byOrder = <int, List<INavDestinationModule>>{};
  for (final tab in tabs ?? const <INavDestinationModule>[]) {
    byOrder.putIfAbsent(tab.order, () => []).add(tab);
  }
  for (final MapEntry(key: order, value: sharing) in byOrder.entries) {
    if (sharing.length < 2) continue;
    yield ProfileProblem(
      code: 'C06',
      description:
          '`INavDestinationModule.order` is the tab sort key and must be '
          'unique, but $order is used by ${_names(sharing)}.',
      action: 'Give each primary destination its own `order` (RULE-24).',
    );
  }

  ProfileProblem? fallbackProblem;
  if (!failed.contains(AppRouter)) {
    try {
      final router = getItOrNull<AppRouter>();
      // Assembles the GoRouter from every contribution; it asserts on a
      // malformed tree (duplicate or missing paths) while it is built.
      if (router != null && router.router.configuration.routes.isEmpty) {
        throw StateError('the router has no routes');
      }
      final fallback = profile.router.fallbackPath;
      if (router != null &&
          fallback != null &&
          router.router.configuration.findMatch(Uri.parse(fallback)).isError) {
        fallbackProblem = ProfileProblem(
          code: 'C11',
          description:
              '`RouterProfile.fallbackPath` is `$fallback`, but the router '
              'registers no route at that path. It is where a signed-in user '
              'lands and where "go home" goes, so the app would open on its '
              'not-found page.',
          action:
              'Set `router: RouterProfile(fallbackPath: ...)` in '
              'apps/${profile.facts.id}/lib/app/app_profile.dart to a path '
              'a composed module registers, or remove it to use the first '
              'tab.',
        );
      }
    } catch (error) {
      yield ProfileProblem(
        code: 'C07',
        description: '`AppRouter.router` failed to assemble: $error',
        action:
            'Fix the route contribution the error names — a module\'s '
            '`IFeatureRouteModule.routes` or `INavDestinationModule.routes`.',
      );
    }
  }
  if (fallbackProblem != null) yield fallbackProblem;

  final classifiers = ErrorHandler.classifiers
      .whereType<DioFailureClassifier>()
      .length;
  if (classifiers != 1) {
    yield ProfileProblem(
      code: 'C08',
      description:
          '`DioFailureClassifier` must hook into `ErrorHandler` exactly once '
          'while the `core` group initialises, but it is registered '
          '$classifiers times.',
      action:
          'Compose `core_network` in the `core` group of `di_groups:` — '
          'without it a `DioException` degrades to the generic unknown '
          'error.',
    );
  }
}

/// `Type` names of [objects], for a message.
String _names(Iterable<Object> objects) =>
    objects.map((o) => o.runtimeType.toString()).join(', ');

/// One row of the catalog next to what the app declared and what the graph
/// registered for it.
final class ContractState {
  const ContractState({
    required this.contract,
    required this.expectation,
    required this.registered,
  });

  final ShellContract<Object> contract;

  /// What the app declared; `null` for a required contract (nothing to
  /// declare) and for an optional one it left out (`C09`).
  final CapabilityExpectation? expectation;

  /// What the graph registered, in registration order.
  final List<Object> registered;
}

/// The result of [checkAppContract].
final class CompositionReport {
  const CompositionReport({
    required this.appId,
    required this.flavor,
    required this.platform,
    required this.states,
    required this.problems,
  });

  final String appId;
  final Flavor flavor;
  final AppPlatform platform;

  /// Every catalog row, in catalog order.
  final List<ContractState> states;

  /// What is wrong; empty when the declaration and the graph agree.
  final List<ProfileProblem> problems;

  bool get isClean => problems.isEmpty;

  /// The report as text: every problem with its code, `Description:` and
  /// `Action:` — the same text at boot and in a failing smoke test.
  String explain() {
    final header = '`$appId` on ${platform.name}, flavor ${flavor.name}';
    if (isClean) {
      return '$header: the declaration matches the graph '
          '(${states.length} contracts checked).';
    }
    return [
      '$header: ${problems.length} composition '
          '${problems.length == 1 ? 'problem' : 'problems'}.',
      for (final problem in problems) '[${problem.code}] $problem',
    ].join('\n\n');
  }
}
