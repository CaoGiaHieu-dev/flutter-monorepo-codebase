import 'dart:io';

import 'package:mustache_template/mustache.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../unused_checker/monorepo_helper.dart';
import 'module_type.dart';

/// Writes a new package's `pubspec.yaml`.
///
/// Internal dependencies are **resolved from disk**, never hardcoded. The
/// template used to carry literal paths like `../../core/core_common`, which
/// named a directory that has never existed in this repository — every package
/// it generated failed `pub get` on its first internal dependency. Locating
/// each package by name means the generator keeps working when packages move,
/// which is the same reason `composer`, `arch_check` and the unused-checkers
/// discover paths instead of assuming them.
class PubspecGenerator {
  String generate(ModuleConfig config) {
    final environment = _rootEnvironment();
    if (config.type == ModuleType.api) {
      // Flutter only: an API package may depend on platform/foundation and
      // Flutter/pub packages and nothing else (arch_check R3), and a
      // navigator stub needs only `BuildContext`.
      return Template(
        File(
          'tools/module_generator/templates/api/pubspec.yaml.mustache',
        ).readAsStringSync(),
      ).renderString({
        'moduleName': config.moduleName,
        'snakeNameInput': config.nameInput,
        'sdkConstraint': environment.sdk,
        'flutterConstraint': environment.flutter,
      });
    }

    final templateString = File(
      'tools/module_generator/templates/common/pubspec.yaml.mustache',
    ).readAsStringSync();
    final template = Template(templateString);

    final values = {
      'moduleName': config.moduleName,
      'sdkConstraint': environment.sdk,
      'flutterConstraint': environment.flutter,
      'isFeature': config.type == ModuleType.feature,
      'isDomain': config.type == ModuleType.domain,
      'isData': config.type == ModuleType.data,
      'isCore': config.type == ModuleType.core,
      'isCustom': config.type == ModuleType.custom,
      'isCoreOrCustom':
          config.type == ModuleType.core || config.type == ModuleType.custom,
      'isProvider': config.smType == StateManagementType.provider,
      'isBloc': config.smType == StateManagementType.bloc,
      // Only the BLoC templates declare Freezed classes (the events and the
      // state data). A domain or data package adds freezed with its first
      // entity or model — declared up front it is reported as unused.
      'usesFreezed':
          config.type == ModuleType.feature &&
          config.smType == StateManagementType.bloc,
      'internalDependencies': _internalDependencies(config),
    };

    return template.renderString(values);
  }

  /// The root `pubspec.yaml`'s `environment:` — every workspace member
  /// declares the same one, so a new package copies it instead of carrying a
  /// literal in the template that drifts from `.fvmrc` (it once said
  /// `>=3.47.0` while the repo pinned 3.47.4).
  static ({String sdk, String flutter}) _rootEnvironment() {
    const fallback = (sdk: '>=3.13.3 <4.0.0', flutter: '>=3.47.4');
    try {
      final env = (loadYaml(
        File('pubspec.yaml').readAsStringSync(),
      ) as Map)['environment'];
      if (env is Map && env['sdk'] is String && env['flutter'] is String) {
        return (sdk: env['sdk'] as String, flutter: env['flutter'] as String);
      }
    } catch (_) {
      // Unreadable root pubspec: fall through to the pinned default.
    }
    return fallback;
  }

  /// The workspace packages a new module of this type starts with.
  ///
  /// Exactly what the rendered templates import, so a fresh module passes
  /// `check_unused_packages` — add `core_network`, `core_storage` and the
  /// rest when the code needs them. Every feature page lays out through
  /// `core_responsive` (`AdaptiveContent`), so a feature declares it from the
  /// start; a BLoC page also renders its loading state with `core_ui_kit`'s
  /// `LoadingWidget` (Provider's `BaseViewWidget` brings its own).
  /// A pre-declared "you will probably want this" dependency is reported as
  /// unused the moment the module exists, which is how generated data
  /// packages used to fail that check out of the box.
  ///
  /// Note `domain` gets `domain_core` and nothing else: a domain package that
  /// depends on a `core_*` package stops being pure Dart, which RULE-03
  /// forbids and `arch_check` R2 blocks. A data package depends on its own
  /// module's `domain_<name>` when that exists (generate the domain first);
  /// core and custom packages start with no workspace dependency at all.
  List<String> _dependencyNames(ModuleConfig config) {
    switch (config.type) {
      case ModuleType.feature:
        return [
          'core_di',
          'core_common',
          'core_base_ui',
          // Every page template wraps its body in `AdaptiveContent`.
          'core_responsive',
          if (config.smType == StateManagementType.provider) ...[
            'provider_state_management',
            // The provider template returns a `Result` from domain_core.
            'domain_core',
          ],
          // The module's API package, when it exists: the feature implements
          // its navigator (`routing/<name>_navigator_impl.dart`).
          if (hasApiPackage(config)) '${config.nameInput}_api',
          if (config.smType == StateManagementType.bloc) ...[
            'bloc_state_management',
            // The bloc template settles a `Result` from domain_core through
            // `emitResult`.
            'domain_core',
            // The BLoC page's loading state is the kit's `LoadingWidget`.
            'core_ui_kit',
          ],
        ];
      case ModuleType.domain:
        // The repository template returns `Result` from domain_core.
        return ['domain_core'];
      case ModuleType.data:
        // The RepositoryImpl template extends data_core's `BaseRepository`
        // and, with a domain to implement, returns its `Result`.
        return [
          'data_core',
          if (hasDomainPackage(config)) ...[
            'domain_core',
            'domain_${config.nameInput}',
          ],
        ];
      case ModuleType.core:
      case ModuleType.custom:
      case ModuleType.api:
        return const [];
    }
  }

  /// Whether a feature's module already has its `<name>_api` — the feature
  /// then declares it and implements its navigator.
  static bool hasApiPackage(ModuleConfig config) =>
      config.type == ModuleType.feature &&
      MonorepoHelper.getPackages(
        _posix(Directory.current.path),
      ).containsKey('${config.nameInput}_api');

  /// Whether the module a data package belongs to already has its
  /// `domain_<name>` — the data template then implements that domain's
  /// repository interface.
  static bool hasDomainPackage(ModuleConfig config) =>
      config.type == ModuleType.data &&
      MonorepoHelper.getPackages(
        _posix(Directory.current.path),
      ).containsKey('domain_${config.nameInput}');

  /// Renders the `name:` / `path:` pairs, indented to sit under `dependencies:`.
  ///
  /// A name that resolves to nothing is reported and skipped rather than
  /// written as a broken path — a pubspec that is missing a dependency says so
  /// on the next `pub get`, while one pointing at a directory that is not there
  /// fails with an error about the path rather than about the package.
  String _internalDependencies(ModuleConfig config) {
    // Both sides absolute, so the relative path between them cannot depend on
    // what the caller's working directory happens to be.
    final root = _posix(Directory.current.path);
    final packages = MonorepoHelper.getPackages(root);
    final moduleDir = p.posix.join(root, _posix(config.modulePath));
    final buffer = StringBuffer();

    for (final name in _dependencyNames(config)) {
      final pkg = packages[name];
      if (pkg == null) {
        stderr.writeln(
          '  ! $name not found in this workspace — skipped. Add it to '
          '${config.modulePath}/pubspec.yaml by hand if the module needs it.',
        );
        continue;
      }
      final relative = p.posix.relative(pkg.rootPath, from: moduleDir);
      buffer.writeln('  $name:');
      buffer.writeln('    path: $relative');
    }
    return buffer.toString().trimRight();
  }

  /// Windows gives back `\` separators; every path here is compared with
  /// `p.posix`, so normalise once at the boundary.
  static String _posix(String path) =>
      p.posix.normalize(path.replaceAll('\\', '/'));
}
