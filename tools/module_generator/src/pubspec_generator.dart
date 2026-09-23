import 'dart:io';

import 'package:mustache_template/mustache.dart';
import 'package:path/path.dart' as p;

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
    final templateString = File(
      'tools/module_generator/templates/common/pubspec.yaml.mustache',
    ).readAsStringSync();
    final template = Template(templateString);

    final values = {
      'moduleName': config.moduleName,
      'isFeature': config.type == ModuleType.feature,
      'isDomain': config.type == ModuleType.domain,
      'isData': config.type == ModuleType.data,
      'isCore': config.type == ModuleType.core,
      'isCustom': config.type == ModuleType.custom,
      'isCoreOrCustom':
          config.type == ModuleType.core || config.type == ModuleType.custom,
      'isProvider': config.smType == StateManagementType.provider,
      'isBloc': config.smType == StateManagementType.bloc,
      // Entities, models and BLoC events are all Freezed; core/custom
      // packages carry no codegen'd data classes by default.
      'usesFreezed': config.type == ModuleType.feature ||
          config.type == ModuleType.domain ||
          config.type == ModuleType.data,
      'internalDependencies': _internalDependencies(config),
    };

    return template.renderString(values);
  }

  /// The workspace packages a new module of this type starts with.
  ///
  /// Mirrors what the shipped packages actually declare. Note `domain` gets
  /// `domain_core` and nothing else: a domain package that depends on a `core_*`
  /// package stops being pure Dart, which rule 26 forbids and `arch_check` R2
  /// blocks.
  List<String> _dependencyNames(ModuleConfig config) {
    switch (config.type) {
      case ModuleType.feature:
        return [
          'core_di',
          'core_common',
          'core_base_ui',
          'core_responsive',
          'core_ui_kit',
          if (config.smType == StateManagementType.provider) ...[
            'provider_state_management',
            // The provider template returns a `Result` from domain_core.
            'domain_core',
          ],
          if (config.smType == StateManagementType.bloc)
            'bloc_state_management',
        ];
      case ModuleType.domain:
        return ['domain_core'];
      case ModuleType.data:
        return ['platform_kernel', 'core_network', 'core_storage', 'data_core'];
      case ModuleType.core:
      case ModuleType.custom:
        return ['platform_kernel'];
    }
  }

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
