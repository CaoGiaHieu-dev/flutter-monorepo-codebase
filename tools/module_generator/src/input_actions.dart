import 'dart:io';

import 'package:path/path.dart' as p;

import '../../unused_checker/monorepo_helper.dart';
import 'module_type.dart';

/// Usage text, printed by `--help` and after every argument error.
const String moduleGeneratorUsage = '''
Usage: dart tools/module_generator/generate.dart <type> <name> [<prefix>] [<SM>] [<route>]

  <type>    1 = Feature  (modules/<name>/feature, package feature_<name>)
            2 = Domain   (modules/<name>/domain,  package domain_<name>)
            3 = Data     (modules/<name>/data,    package data_<name>)
            4 = Core     (platform/<name>,        package core_<name>)
            5 = Custom   (platform/<name>,        package <prefix>_<name>)
  <name>    lowercase_with_underscores, starting with a letter (profile, user_profile)
  <prefix>  type 5 only: the package-name prefix. Pass "" for every other type.
  <SM>      type 1 only: 1 = Provider, 2 = BLoC, 3 = none
  <route>   type 1 only: 1 = IFeatureRouteModule (stack routes),
                         2 = INavDestinationModule (primary nav tab), 3 = none

Examples:
  dart tools/module_generator/generate.dart 1 profile "" 1 1   # Feature + Provider + stack routes
  dart tools/module_generator/generate.dart 1 chat "" 2 2      # Feature + BLoC + nav tab
  dart tools/module_generator/generate.dart 2 payment          # Domain micro-package
  dart tools/module_generator/generate.dart 3 payment          # Data micro-package
  dart tools/module_generator/generate.dart 4 analytics        # core_analytics
  dart tools/module_generator/generate.dart 5 billing acme     # acme_billing at platform/billing

Run with no arguments on a terminal to be prompted for everything; a missing
<SM> or <route> for a feature is prompted for too. Without a terminal every
value must be passed.''';

/// Dart package names: lowercase letters, digits and underscores, starting
/// with a letter. (Pub also allows a leading underscore; this repo's naming
/// does not use it.)
final RegExp _packageNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Identifiers pub refuses as package names.
const Set<String> _reservedWords = {
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', //
  'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
  'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'for', 'function', 'get', 'hide',
  'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
  'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
  'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
};

class InputActions {
  /// Prints [message] and the usage to stderr, then exits 64 (usage error).
  Never _usageError(String message) {
    stderr.writeln('[ERROR] $message');
    stderr.writeln('');
    stderr.writeln(moduleGeneratorUsage);
    exit(64);
  }

  /// Reads one line, or fails when there is nobody to answer.
  ///
  /// End of input counts as "nobody" too, not as an empty answer:
  /// `stdin.hasTerminal` reports true for `/dev/null` (a character device),
  /// and a run from CI with `</dev/null` used to take every default and
  /// generate a module nobody chose.
  String _prompt(String question) {
    if (!stdin.hasTerminal) _noAnswer(question);
    stdout.write(question);
    final line = stdin.readLineSync();
    if (line == null) {
      stdout.writeln();
      _noAnswer(question);
    }
    return line.trim();
  }

  Never _noAnswer(String question) => _usageError(
    'Missing argument, and nobody to answer "${question.trim()}" '
    '(stdin is not a terminal, or it ended). Pass every argument on the command line.',
  );

  void _validateName(String value, String what) {
    if (!_packageNamePattern.hasMatch(value)) {
      _usageError(
        '$what "$value" is invalid: use lowercase letters, digits and "_", '
        'starting with a letter (e.g. user_profile).',
      );
    }
    if (_reservedWords.contains(value)) {
      _usageError('$what "$value" is a Dart keyword — pub refuses it.');
    }
  }

  /// Exits 64 when a pubspec anywhere in the repository already declares
  /// `name: [packageName]`.
  void _assertPackageNameFree(String packageName, String modulePath) {
    final root = p.posix.normalize(
      Directory.current.path.replaceAll('\\', '/'),
    );
    final existing = MonorepoHelper.getPackages(root)[packageName];
    if (existing == null) return;
    final where = p.posix.relative(existing.rootPath, from: root);
    _usageError(
      'Package "$packageName" already exists at "$where" — pub does not allow '
      'two packages with the same name in one workspace. Choose another name '
      '(this would have created "$modulePath"). Nothing was written.',
    );
  }

  ModuleConfig parseInput(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      stdout.writeln(moduleGeneratorUsage);
      exit(0);
    }
    final flag = args.where((a) => a.startsWith('-')).firstOrNull;
    if (flag != null) _usageError('Unknown flag: $flag');
    if (args.length > 5) {
      _usageError('Too many arguments (${args.length}, at most 5).');
    }
    if (args.length == 1) {
      _usageError('Missing <name>.');
    }

    String? typeInput;
    String? nameInput;
    String? typeDirInput;

    if (args.length >= 2) {
      typeInput = args[0];
      nameInput = args[1];
      if (args.length >= 3) {
        typeDirInput = args[2];
      }
    } else {
      stdout.writeln('\nChoose the module type to create:');
      stdout.writeln('1. Feature Package (modules/<name>/feature/)');
      stdout.writeln('2. Domain Micro-Package (modules/<name>/domain/)');
      stdout.writeln('3. Data Micro-Package (modules/<name>/data/)');
      stdout.writeln('4. Core Package (platform/)');
      stdout.writeln(
        '5. Custom Package (platform/<name>, prefix of your choice)',
      );
      typeInput = _prompt('Your choice: ');
    }

    ModuleType type;
    String typeDir;
    String typeName;

    switch (typeInput) {
      case '1':
        type = ModuleType.feature;
        typeDir = 'modules/<name>/feature';
        typeName = 'feature';
      case '2':
        type = ModuleType.domain;
        typeDir = 'modules/<name>/domain';
        typeName = 'domain';
      case '3':
        type = ModuleType.data;
        typeDir = 'modules/<name>/data';
        typeName = 'data';
      case '4':
        type = ModuleType.core;
        typeDir = 'platform';
        typeName = 'core';
      case '5':
        type = ModuleType.custom;
        typeDir = 'platform';
        typeName = '';
      default:
        _usageError('Invalid <type>: "$typeInput" (1-5).');
    }

    if (type != ModuleType.feature && args.length > 3) {
      _usageError('<SM> and <route> apply to type 1 (Feature) only.');
    }

    if (type == ModuleType.custom) {
      if (args.length < 3) {
        typeDirInput = _prompt(
          '\nPackage-name prefix (e.g. analytics, payments): ',
        );
      }
      if (typeDirInput == null || typeDirInput.isEmpty) {
        _usageError('<prefix> must not be empty for type 5.');
      }
      // A layer prefix would make arch_check classify a platform package as
      // that layer, and a module layer belongs at modules/<name>/<layer> —
      // types 1-3 build exactly that.
      const reserved = {'feature', 'features', 'domain', 'data', 'core'};
      if (reserved.contains(typeDirInput)) {
        _usageError(
          '"$typeDirInput" is a layer prefix — use types 1-4.',
        );
      }
      _validateName(typeDirInput, 'Prefix');
      // A custom package is a platform package with its own name prefix:
      // `<prefix>_<name>` at `platform/<name>`.
      typeName = typeDirInput;
    } else if (typeDirInput != null && typeDirInput.isNotEmpty) {
      _usageError(
        '<prefix> applies to type 5 only — pass "" for type $typeInput.',
      );
    }

    if (args.length < 2) {
      nameInput = _prompt(
        '\nModule name (e.g. profile, analytics, core): ',
      );
    }
    if (nameInput == null || nameInput.isEmpty) {
      _usageError('Module name must not be empty.');
    }
    _validateName(nameInput, 'Module name');

    StateManagementType smType = StateManagementType.none;
    FeatureRouteContribution routeContribution =
        FeatureRouteContribution.featureRoute;
    if (type == ModuleType.feature) {
      String? smInput;
      if (args.length >= 4) {
        smInput = args[3];
      } else {
        stdout.writeln('\nChoose the state management for the module:');
        stdout.writeln('1. Provider');
        stdout.writeln('2. BLoC');
        stdout.writeln('3. None');
        final input = _prompt('Your choice (default 1): ');
        smInput = input.isEmpty ? '1' : input;
      }

      smType = switch (smInput) {
        '1' => StateManagementType.provider,
        '2' => StateManagementType.bloc,
        '3' => StateManagementType.none,
        _ => _usageError('Invalid <SM>: "$smInput" (1, 2 or 3).'),
      };

      String? routeInput;
      if (args.length >= 5) {
        routeInput = args[4];
      } else {
        stdout.writeln(
          '\nHow the feature contributes routes to the app shell (dynamic DI):',
        );
        stdout.writeln(
          '1. IFeatureRouteModule — stack screens pushed on the app (auth, onboarding, detail…)',
        );
        stdout.writeln(
          '2. INavDestinationModule — a primary navigation destination (ONLY for a real top-level tab)',
        );
        stdout.writeln('3. No route stub');
        final input = _prompt('Your choice (default 1): ');
        routeInput = input.isEmpty ? '1' : input;
      }

      routeContribution = switch (routeInput) {
        '1' => FeatureRouteContribution.featureRoute,
        '2' => FeatureRouteContribution.dashboardTab,
        '3' => FeatureRouteContribution.none,
        _ => _usageError('Invalid <route>: "$routeInput" (1, 2 or 3).'),
      };
    }

    final moduleName = typeName.isEmpty ? nameInput : '${typeName}_$nameInput';
    _validateName(moduleName, 'Package name');
    // A module's layers sit side by side under the module:
    // `modules/<name>/{domain,data,feature}`. Core and custom packages live
    // at `platform/<name>`.
    final isModuleLayer =
        type == ModuleType.feature ||
        type == ModuleType.domain ||
        type == ModuleType.data;
    final modulePath = isModuleLayer
        ? 'modules/$nameInput/$typeName'
        : '$typeDir/$nameInput';
    final moduleDir = Directory(modulePath);

    // Pub resolves a workspace by package NAME, so two members sharing one
    // fails `pub get` — and only after composer has rewritten the manifests,
    // the workspace list and injection.dart. Worse, a type-5 name can land in
    // a fresh directory yet repeat an existing name (`5 shell platform_app`
    // is `platform_app_shell`, already at platform/app_shell), and `2 core` /
    // `3 core` are domain_core / data_core. Checked before anything is
    // written, against every pubspec in the repository.
    _assertPackageNameFree(moduleName, modulePath);

    // Never overwrite: deleting an existing package here would happen before
    // the rollback snapshot, so nothing could restore it.
    if (moduleDir.existsSync()) {
      stderr.writeln(
        '[ERROR] Directory "$modulePath" already exists. '
        'Remove it or choose another module name, then run again.',
      );
      exit(1);
    }

    return ModuleConfig(
      type: type,
      typeDir: typeDir,
      typeName: typeName,
      nameInput: nameInput,
      smType: smType,
      routeContribution: routeContribution,
      moduleName: moduleName,
      modulePath: modulePath,
    );
  }
}
