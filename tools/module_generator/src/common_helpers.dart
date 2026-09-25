import 'dart:io';

import 'package:mustache_template/mustache.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../shared/app_locator.dart';
import '../../shared/toolchain.dart' as toolchain;
import 'module_type.dart';
import 'pubspec_generator.dart';

class CommonHelpers {
  static void createDir(String path) {
    Directory(path).createSync(recursive: true);
    stdout.writeln('  -> Created directory: $path');
  }

  // ---------------------------------------------------------------------------
  // Toolchain resolution (FVM vs global SDK)
  // ---------------------------------------------------------------------------

  /// Whether toolchain commands should be prefixed with `fvm` — the shared
  /// two-signal detection in `tools/shared/toolchain.dart`.
  static bool get useFvm => toolchain.useFvm;

  /// Fails fast when the toolchain this run needs is not callable.
  ///
  /// Called before any shared file is touched, so an unusable environment is
  /// reported while the workspace is still pristine.
  static void assertToolchainAvailable() {
    if (useFvm) {
      stdout.writeln('[INFO] FVM config detected. Using "fvm dart/flutter".');
      return;
    }

    for (final executable in const ['dart', 'flutter']) {
      try {
        final result = Process.runSync(executable, [
          '--version',
        ], runInShell: true);
        if (result.exitCode != 0) {
          throw Exception(
            '"$executable --version" exited with ${result.exitCode}',
          );
        }
      } on ProcessException {
        throw Exception(
          '"$executable" is not on PATH and no usable FVM setup was found. '
          'Install the Flutter SDK, or run "dart pub global activate fvm", before generating a module.',
        );
      }
    }
    stdout.writeln('[INFO] No FVM. Using the global "dart/flutter".');
  }

  /// Runs `dart <args>`, routed through FVM when this repo uses it.
  static Future<void> runDart(
    List<String> args, {
    String? workingDirectory,
  }) {
    return useFvm
        ? runCommand('fvm', [
            'dart',
            ...args,
          ], workingDirectory: workingDirectory)
        : runCommand('dart', args, workingDirectory: workingDirectory);
  }

  /// Runs `flutter <args>`, routed through FVM when this repo uses it.
  static Future<void> runFlutter(
    List<String> args, {
    String? workingDirectory,
  }) {
    return useFvm
        ? runCommand('fvm', [
            'flutter',
            ...args,
          ], workingDirectory: workingDirectory)
        : runCommand('flutter', args, workingDirectory: workingDirectory);
  }

  // ---------------------------------------------------------------------------
  // Rollback of shared-file mutations
  // ---------------------------------------------------------------------------

  /// Files outside the new module that generation rewrites in place: every
  /// app's `app_manifest.yaml` ([registerInAppManifests]), what
  /// `composer sync` regenerates from them — the root `pubspec.yaml`, each
  /// app's `pubspec.yaml` and `lib/di/injection.dart` — and the committed
  /// `pubspec.lock` that `pub get` rewrites.
  ///
  /// Not here: what `pub get` and `build_runner` write that git does not
  /// track — `.dart_tool/package_config.json`, each app's
  /// `injection.config.dart`, every package's `module.module.dart`. Restoring
  /// a snapshot of those would be wrong the moment codegen had legitimately
  /// changed them, so [rollback] regenerates them instead.
  ///
  /// A failure partway through would leave these half-edited — a module
  /// registered in the workspace whose directory was never finished building,
  /// which then breaks `pub get` for everyone. Hence the backup-and-restore
  /// around them.
  static List<String> get sharedMutatedFiles => [
    'pubspec.yaml',
    'pubspec.lock',
    for (final app in discoverApps()) ...[
      '${app.dir}/app_manifest.yaml',
      '${app.dir}/pubspec.yaml',
      '${app.dir}/lib/di/injection.dart',
    ],
  ];

  static final Map<String, String?> _sharedFileSnapshots = {};
  static String? _createdModulePath;
  static bool _workspaceResolved = false;
  static bool _codegenStarted = false;

  /// Call just before `pub get`: from here on `.dart_tool/package_config.json`
  /// may list the new module, so [rollback] must resolve the workspace again.
  static void noteWorkspaceResolving() => _workspaceResolved = true;

  /// Call just before `build_runner`: from here on the untracked generated
  /// files (`injection.config.dart`, `module.module.dart`) may reference the
  /// new module, so [rollback] must regenerate them.
  static void noteCodegenStarted() => _codegenStarted = true;

  /// The command, as the user would type it — `fvm dart …` under FVM.
  static String _commandLine(bool dart, List<String> args) => [
    if (useFvm) 'fvm',
    if (dart) 'dart' else 'flutter',
    ...args,
  ].join(' ');

  static const List<String> _pubGetArgs = ['pub', 'get'];
  static const List<String> _buildRunnerArgs = [
    'run',
    'build_runner',
    'build',
    '--workspace',
  ];

  /// Snapshots every shared file before the first mutation — plus
  /// [extraFiles], files of *another* package this run edits or creates
  /// (an API package wires its existing feature).
  ///
  /// A `null` value records "did not exist", so restore deletes rather than
  /// resurrecting a file generation created.
  static void snapshotSharedFiles(
    String modulePath, {
    List<String> extraFiles = const [],
  }) {
    _createdModulePath = modulePath;
    _workspaceResolved = false;
    _codegenStarted = false;
    _sharedFileSnapshots.clear();
    for (final path in [...sharedMutatedFiles, ...extraFiles]) {
      final file = File(path);
      _sharedFileSnapshots[path] = file.existsSync()
          ? file.readAsStringSync()
          : null;
    }
  }

  /// Restores the snapshotted files, removes the half-built module, and —
  /// when generation got that far — resolves the workspace and reruns
  /// `build_runner` so the untracked generated files stop referencing it.
  ///
  /// Restoring the tracked files alone is not enough after a late failure:
  /// `build_runner` had already rewritten every app's `injection.config.dart`
  /// to import the new package, and with the package deleted the app no
  /// longer compiles — while this used to report the workspace as clean.
  ///
  /// Best-effort by design: it reports what it could not undo, with the
  /// commands to finish by hand, instead of throwing, because it runs while
  /// another error is already propagating. It claims a clean workspace only
  /// when every step succeeded.
  static Future<void> rollback() async {
    final failures = <String>[];

    _sharedFileSnapshots.forEach((path, original) {
      try {
        final file = File(path);
        if (original == null) {
          if (file.existsSync()) file.deleteSync();
        } else {
          file.writeAsStringSync(original);
        }
      } catch (e) {
        failures.add('$path ($e)');
      }
    });

    final modulePath = _createdModulePath;
    if (modulePath != null) {
      try {
        final dir = Directory(modulePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        // modules/<name>/ is left empty when <layer> was its only child.
        final parent = dir.parent;
        if (parent.existsSync() && parent.listSync().isEmpty) {
          parent.deleteSync();
        }
      } catch (e) {
        failures.add('$modulePath ($e)');
      }
    }

    // Regenerate what git does not track, in dependency order: build_runner
    // needs a package_config.json that no longer lists the deleted module.
    final pending = <String>[
      if (_workspaceResolved || _codegenStarted)
        _commandLine(false, _pubGetArgs),
      if (_codegenStarted) _commandLine(true, _buildRunnerArgs),
    ];
    if (failures.isEmpty && pending.isNotEmpty) {
      stderr.writeln(
        '[ROLLBACK] Regenerating untracked generated files so they no '
        'longer reference the removed module...',
      );
      try {
        if (_workspaceResolved || _codegenStarted) {
          await runFlutter(_pubGetArgs);
          pending.removeAt(0);
        }
        if (_codegenStarted) {
          await runDart(_buildRunnerArgs);
          pending.removeAt(0);
        }
      } catch (e) {
        failures.add('regenerate generated files ($e)');
      }
    }

    if (failures.isEmpty) {
      stderr.writeln(
        '[ROLLBACK] Every change was undone. The workspace is back to its original state.',
      );
      return;
    }

    stderr.writeln(
      '[ROLLBACK] The workspace is NOT clean. These could not be undone — '
      'clean them up by hand:',
    );
    for (final failure in failures) {
      stderr.writeln('  - $failure');
    }
    if (pending.isNotEmpty) {
      stderr.writeln(
        '[ROLLBACK] Then run these from the repo root so the generated files '
        '(injection.config.dart, module.module.dart) stop referencing the '
        'removed module:',
      );
      for (final command in pending) {
        stderr.writeln('    $command');
      }
    }
  }

  static String toPascalCase(String snakeCase) {
    return snakeCase
        .split('_')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1);
        })
        .join('');
  }

  static Future<void> runCommand(
    String command,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final result = await Process.start(
      command,
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await result.exitCode;
    if (exitCode != 0) {
      throw Exception(
        'Command "$command ${args.join(' ')}" failed with exit code $exitCode',
      );
    }
  }

  /// Adds the new module to every app manifest — or, with [apps], only to
  /// the manifests whose `app.id` is listed — then leaves the wiring alone.
  ///
  /// This used to patch `apps/mobile/pubspec.yaml` and `apps/mobile/lib/di/injection.dart`
  /// directly. Both now live between `composer:managed` markers, so writing
  /// into them by hand puts the tree straight into the drift that
  /// `composer verify` fails CI on — and the marker text the old code looked
  /// for (`externalPackageModulesBefore: [`) no longer exists, so it had
  /// silently stopped working.
  ///
  /// The manifest is the only hand-edited input; `generate.dart` runs
  /// `composer sync` next to regenerate the rest.
  ///
  /// Presence is decided by parsing the manifest, never by substring: a line
  /// test once took `core_net` for registered because `core_network` contains
  /// it, and the package silently joined no app. Every write is re-parsed and
  /// checked, and a manifest the edit could not register in throws — the
  /// caller rolls back rather than leaving a package nothing composes.
  static void registerInAppManifests(
    String packageName,
    ModuleType moduleType,
    String moduleName, {
    List<String>? apps,
    String root = '.',
  }) {
    final manifests = [
      for (final app in discoverApps(root))
        if (apps == null || apps.contains(app.id))
          File(p.join(root, app.dir, 'app_manifest.yaml')),
    ];
    if (manifests.isEmpty) {
      stdout.writeln(
        '  !! No app_manifest.yaml found — skipping app composition.',
      );
      return;
    }

    // `feature` / `domain` / `data` are layers of a module; a core or custom
    // package is a platform package that joins a DI group directly.
    final layer = switch (moduleType) {
      ModuleType.feature => 'feature',
      ModuleType.domain => 'domain',
      ModuleType.data => 'data',
      ModuleType.api => 'api',
      ModuleType.core || ModuleType.custom => null,
    };

    bool isRegistered(String text) => layer != null
        ? _hasModuleLayer(text, moduleName, layer)
        : _hasPlatformPackage(text, packageName);

    if (apps != null) {
      stdout.writeln('  -> --apps: composing into ${apps.join(', ')} only');
    }
    for (final manifest in manifests) {
      final original = manifest.readAsStringSync();
      if (isRegistered(original)) {
        stdout.writeln('  -> Already listed in ${manifest.path}');
        continue;
      }

      final lines = original.split('\n');
      if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
      if (layer != null) {
        _addModuleLayer(lines, moduleName, layer);
      } else {
        _addPlatformPackage(lines, packageName);
      }
      final updated = '${lines.join('\n')}\n';

      if (!isRegistered(updated)) {
        throw Exception(
          'Could not add "$packageName" to ${manifest.path}: no '
          '${layer != null ? '`modules:` list' : '`core` DI group (`packages:`)'} '
          'in the expected format. Add it by hand, then run '
          '`dart tools/composer/composer.dart sync`.',
        );
      }
      manifest.writeAsStringSync(updated);
      stdout.writeln('  -> Added to ${manifest.path}');
    }
  }

  /// Parses [text] as a manifest; a malformed one is reported, not guessed at.
  static Map<Object?, Object?> _parseManifest(String text) {
    final doc = loadYaml(text);
    if (doc is! Map) {
      throw Exception('app_manifest.yaml is not a YAML map.');
    }
    return doc;
  }

  /// Whether `modules:` lists `{ id: moduleName }` with [layer] among its
  /// `layers`.
  static bool _hasModuleLayer(String text, String moduleName, String layer) {
    final modules = _parseManifest(text)['modules'];
    if (modules is! List) return false;
    for (final entry in modules) {
      if (entry is Map && entry['id'] == moduleName) {
        final layers = entry['layers'];
        if (layers is List && layers.contains(layer)) return true;
      }
    }
    return false;
  }

  /// Whether any DI group's `packages:` — or `extra_dependencies:` — names
  /// [packageName] exactly.
  static bool _hasPlatformPackage(String text, String packageName) {
    final doc = _parseManifest(text);
    final groups = doc['di_groups'];
    if (groups is List) {
      for (final group in groups) {
        if (group is Map) {
          final packages = group['packages'];
          if (packages is List && packages.contains(packageName)) return true;
        }
      }
    }
    final extra = doc['extra_dependencies'];
    return extra is List && extra.contains(packageName);
  }

  /// `- { id: <name>, layers: [...] }` — appended, or extended if present.
  static void _addModuleLayer(
    List<String> lines,
    String moduleName,
    String layer,
  ) {
    final existing = lines.indexWhere(
      (l) => RegExp(
        '^\\s*-\\s*\\{\\s*id:\\s*${RegExp.escape(moduleName)}\\s*,',
      ).hasMatch(l),
    );
    if (existing != -1) {
      lines[existing] = lines[existing].replaceFirst(
        RegExp(r'layers:\s*\['),
        'layers: [$layer, ',
      );
      return;
    }
    final modulesIndex = lines.indexWhere((l) => l.trimRight() == 'modules:');
    if (modulesIndex == -1) return;
    // After the last `- ` item; comments and blank lines between items are
    // skipped, the first other line (a top-level key) ends the list.
    var lastItem = modulesIndex;
    for (var i = modulesIndex + 1; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (!trimmed.startsWith('- ')) break;
      lastItem = i;
    }
    lines.insert(lastItem + 1, '  - { id: $moduleName, layers: [$layer] }');
  }

  /// A platform package joins the `core` DI group — after its last entry.
  ///
  /// Handles both list styles the manifests use: a block list (comments
  /// between items allowed) and a flow list (`packages: [a, b]`).
  static void _addPlatformPackage(List<String> lines, String packageName) {
    final group = lines.indexWhere(
      (l) => RegExp(r'^\s*-\s*name:\s*core\s*$').hasMatch(l),
    );
    if (group == -1) return;
    final groupIndent = lines[group].indexOf('-');

    for (var i = group + 1; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final indent = line.length - trimmed.length;
      // Left the group: the next `- name:` or a top-level key.
      if (indent <= groupIndent) return;

      final flow = RegExp(r'^(\s*packages:\s*\[)(.*)\](.*)$').firstMatch(line);
      if (flow != null) {
        final items = flow.group(2)!.trim();
        lines[i] =
            '${flow.group(1)}${items.isEmpty ? packageName : '$items, $packageName'}]${flow.group(3)}';
        return;
      }
      if (RegExp(r'^\s*packages:\s*$').hasMatch(line)) {
        var lastItem = -1;
        var itemIndent = indent + 2;
        for (var j = i + 1; j < lines.length; j++) {
          final t = lines[j].trimLeft();
          if (t.isEmpty || t.startsWith('#')) continue;
          final ind = lines[j].length - t.length;
          if (!t.startsWith('- ') || ind < indent) break;
          lastItem = j;
          itemIndent = ind;
        }
        final at = lastItem == -1 ? i + 1 : lastItem + 1;
        lines.insert(at, '${' ' * itemIndent}- $packageName');
        return;
      }
    }
  }

  static void createL10nScaffold(
    String modulePath,
    String moduleName,
    String nameInput,
  ) {
    final pascalName = toPascalCase(moduleName);
    final pascalNameInput = toPascalCase(nameInput);
    final values = {
      'moduleName': moduleName,
      'pascalName': pascalName,
      'pascalNameInput': pascalNameInput,
      'snakeName': nameInput,
    };

    // l10n.yaml
    final l10nTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/l10n.yaml.mustache',
      ).readAsStringSync(),
    );
    File(
      '$modulePath/l10n.yaml',
    ).writeAsStringSync(l10nTemplate.renderString(values));

    // en.arb
    final enArbTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/en.arb.mustache',
      ).readAsStringSync(),
    );
    File(
      '$modulePath/assets/language/en.arb',
    ).writeAsStringSync(enArbTemplate.renderString(values));

    // vi.arb
    final viArbTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/vi.arb.mustache',
      ).readAsStringSync(),
    );
    File(
      '$modulePath/assets/language/vi.arb',
    ).writeAsStringSync(viArbTemplate.renderString(values));

    // lib/src/localization/<nameInput>_localization_impl.dart — the
    // IFeatureLocalization registration. Not in lib/di/, which holds the
    // DI module and its generated file only.
    final locTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/localization.dart.mustache',
      ).readAsStringSync(),
    );
    Directory('$modulePath/lib/src/localization').createSync(recursive: true);
    File(
      '$modulePath/lib/src/localization/${nameInput}_localization_impl.dart',
    ).writeAsStringSync(locTemplate.renderString(values));

    // lib/src/extensions/l10n_<nameInput>_extension.dart
    final extTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/localization_extension.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '$modulePath/lib/src/extensions/l10n_${nameInput}_extension.dart',
    ).writeAsStringSync(extTemplate.renderString(values));

    stdout.writeln(
      '  -> Created l10n.yaml, the .arb files, the l10n extension and its DI registration',
    );
  }

  static String toCamelCase(String snakeCase) {
    final pascal = toPascalCase(snakeCase);
    if (pascal.isEmpty) return '';
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

  /// `user_profile` -> `USER_PROFILE`, matching the repo's constant style.
  static String toScreamingSnakeCase(String snakeCase) {
    return snakeCase.toUpperCase();
  }

  static void createFeatureTemplates(ModuleConfig config) {
    final pascalNameInput = toPascalCase(config.nameInput);
    final camelNameInput = toCamelCase(config.nameInput);
    final snakeNameInput = config.nameInput;

    final values = <String, Object>{
      'moduleName': config.moduleName,
      'pascalName': toPascalCase(config.moduleName),
      'pascalNameInput': pascalNameInput,
      'camelNameInput': camelNameInput,
      'snakeNameInput': snakeNameInput,
      'snakeName': snakeNameInput,
      'screamingNameInput': toScreamingSnakeCase(snakeNameInput),
      'isProvider': config.smType == StateManagementType.provider,
      'isBloc': config.smType == StateManagementType.bloc,
      'isNone': config.smType == StateManagementType.none,
    };

    String pageTemplatePath;
    if (config.smType == StateManagementType.provider) {
      pageTemplatePath = 'tools/module_generator/templates/feature/provider/page.dart.mustache';

      final providerTpl = Template(
        File(
          'tools/module_generator/templates/feature/provider/provider.dart.mustache',
        ).readAsStringSync(),
      );
      File(
        '${config.modulePath}/lib/src/provider/${snakeNameInput}_provider.dart',
      ).writeAsStringSync(providerTpl.renderString(values));
    } else if (config.smType == StateManagementType.bloc) {
      pageTemplatePath =
          'tools/module_generator/templates/feature/bloc/page.dart.mustache';

      final blocTpl = Template(
        File(
          'tools/module_generator/templates/feature/bloc/bloc.dart.mustache',
        ).readAsStringSync(),
      );
      final eventTpl = Template(
        File(
          'tools/module_generator/templates/feature/bloc/event.dart.mustache',
        ).readAsStringSync(),
      );
      final stateTpl = Template(
        File(
          'tools/module_generator/templates/feature/bloc/state.dart.mustache',
        ).readAsStringSync(),
      );

      // Flat `bloc/`, matching feature_home — the `part` files must sit beside
      // the bloc, and the repo does not nest one folder per bloc.
      File(
        '${config.modulePath}/lib/src/bloc/${snakeNameInput}_bloc.dart',
      ).writeAsStringSync(blocTpl.renderString(values));
      File(
        '${config.modulePath}/lib/src/bloc/${snakeNameInput}_event.dart',
      ).writeAsStringSync(eventTpl.renderString(values));
      File(
        '${config.modulePath}/lib/src/bloc/${snakeNameInput}_state.dart',
      ).writeAsStringSync(stateTpl.renderString(values));
    } else {
      pageTemplatePath =
          'tools/module_generator/templates/feature/default/page.dart.mustache';
    }

    final pageTpl = Template(File(pageTemplatePath).readAsStringSync());
    File(
      '${config.modulePath}/lib/src/pages/${snakeNameInput}_page.dart',
    ).writeAsStringSync(pageTpl.renderString(values));

    // 2. Create route path constants (in utils/, per the repo-wide rule that a
    // package keeps its constants there) and the route_module file.
    final pathTpl = Template(
      File(
        'tools/module_generator/templates/feature/routing/path.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/utils/${snakeNameInput}_path.dart',
    ).writeAsStringSync(pathTpl.renderString(values));

    final routeModuleTpl = Template(
      File(
        'tools/module_generator/templates/feature/routing/route_module.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/routing/${snakeNameInput}_route_module.dart',
    ).writeAsStringSync(routeModuleTpl.renderString(values));

    if (PubspecGenerator.hasApiPackage(config)) {
      writeNavigatorImpl(config.modulePath, config.nameInput);
    }

    createFeatureTests(config, values);

    stdout.writeln(
      '  -> Created the ${config.smType.name.toUpperCase()}, route and page templates',
    );
  }

  /// `lib/src/routing/<name>_navigator_impl.dart` in the feature at
  /// [featurePath]: implements `<Name>Navigator` from `<name>_api` with the
  /// feature's own `<Name>Route`.
  static String navigatorImplPath(String featurePath, String nameInput) =>
      '$featurePath/lib/src/routing/${nameInput}_navigator_impl.dart';

  static void writeNavigatorImpl(String featurePath, String nameInput) {
    final tpl = Template(
      File(
        'tools/module_generator/templates/feature/routing/navigator_impl.dart.mustache',
      ).readAsStringSync(),
    );
    File(navigatorImplPath(featurePath, nameInput)).writeAsStringSync(
      tpl.renderString({
        'moduleName': 'feature_$nameInput',
        'snakeNameInput': nameInput,
        'pascalNameInput': toPascalCase(nameInput),
      }),
    );
    stdout.writeln(
      '  -> Implemented ${toPascalCase(nameInput)}Navigator in '
      '${navigatorImplPath(featurePath, nameInput)}',
    );
  }

  /// API scaffold: the navigator contract other features reach this module
  /// through. The barrel is written by the barrel generator afterwards.
  static void createApiTemplates(ModuleConfig config) {
    final tpl = Template(
      File(
        'tools/module_generator/templates/api/navigator.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/navigators/${config.nameInput}_navigator.dart',
    ).writeAsStringSync(tpl.renderString(_layerValues(config)));
  }

  /// The feature of the module an API package is generated for, when it
  /// exists and still has the route its generator wrote — the one an
  /// API's navigator can be implemented with, without guessing.
  static String? featureToWire(String nameInput) {
    final feature = 'modules/$nameInput/feature';
    final route = File(
      '$feature/lib/src/routing/${nameInput}_route_module.dart',
    );
    if (!File('$feature/pubspec.yaml').existsSync() || !route.existsSync()) {
      return null;
    }
    final declaresRoute = RegExp(
      'class\\s+${toPascalCase(nameInput)}Route\\b',
    ).hasMatch(route.readAsStringSync());
    return declaresRoute ? feature : null;
  }

  /// Makes the existing feature at [featurePath] declare `<name>_api` (a
  /// path dependency, first under `dependencies:`) and implement its
  /// navigator.
  static void wireFeatureToApi(String featurePath, String nameInput) {
    final pubspec = File('$featurePath/pubspec.yaml');
    final lines = pubspec.readAsLinesSync();
    final at = lines.indexWhere((l) => l.trimRight() == 'dependencies:');
    if (at == -1) {
      throw Exception('$featurePath/pubspec.yaml has no `dependencies:`.');
    }
    if (!lines.any((l) => l.trimRight() == '  ${nameInput}_api:')) {
      lines.insertAll(at + 1, ['  ${nameInput}_api:', '    path: ../api']);
      pubspec.writeAsStringSync('${lines.join('\n')}\n');
      stdout.writeln('  -> $featurePath now depends on ${nameInput}_api');
    }
    writeNavigatorImpl(featurePath, nameInput);
  }

  /// The tests a feature starts with, so `flutter test` has something to run
  /// the moment the package exists (CI Gate 3 runs every `test/` it finds):
  ///
  /// * `test/<name>_page_test.dart` — the page under `ResponsiveInit` and the
  ///   feature's localizations, with its controller provided the way the
  ///   route provides it, on a phone and a tablet window.
  /// * `test/<name>_provider_test.dart` (Provider) or
  ///   `test/<name>_bloc_test.dart` (BLoC) — the controller on its own.
  ///   Nothing controller-specific for SM = none.
  static void createFeatureTests(
    ModuleConfig config,
    Map<String, Object> values,
  ) {
    const dir = 'tools/module_generator/templates/feature/test';
    final testDir = '${config.modulePath}/test';
    createDir(testDir);
    void render(String template, String out) {
      File('$testDir/$out').writeAsStringSync(
        Template(File('$dir/$template').readAsStringSync())
            .renderString(values),
      );
    }

    final name = config.nameInput;
    render('page_test.dart.mustache', '${name}_page_test.dart');
    switch (config.smType) {
      case StateManagementType.provider:
        render('provider_test.dart.mustache', '${name}_provider_test.dart');
      case StateManagementType.bloc:
        render('bloc_test.dart.mustache', '${name}_bloc_test.dart');
      case StateManagementType.none:
        break;
    }
  }

  /// The values every non-feature template is rendered with.
  static Map<String, Object> _layerValues(ModuleConfig config) => {
    'moduleName': config.moduleName,
    'pascalNameInput': toPascalCase(config.nameInput),
    'snakeNameInput': config.nameInput,
  };

  /// Domain scaffold: the module's repository contract, so the package
  /// starts out using the `domain_core` it declares.
  static void createDomainTemplates(ModuleConfig config) {
    final tpl = Template(
      File(
        'tools/module_generator/templates/domain/repository.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/repositories/i_${config.nameInput}_repository.dart',
    ).writeAsStringSync(tpl.renderString(_layerValues(config)));
  }

  /// Data scaffold: a `RepositoryImpl` on data_core's `BaseRepository`,
  /// implementing and registered as the domain's contract when [hasDomain].
  static void createDataTemplates(
    ModuleConfig config, {
    required bool hasDomain,
  }) {
    final tpl = Template(
      File(
        'tools/module_generator/templates/data/repository_impl.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/repositories_impl/${config.nameInput}_repository_impl.dart',
    ).writeAsStringSync(
      tpl.renderString({..._layerValues(config), 'hasDomain': hasDomain}),
    );
    if (!hasDomain) {
      stdout.writeln(
        '  !! No domain_${config.nameInput} yet: the RepositoryImpl implements '
        'no interface — generate the domain, then wire it up '
        '(see the comment in the file).',
      );
    }
  }

  /// The `order` for a newly generated `INavDestinationModule`: 10 above the
  /// highest order any existing destination under `modules/*/feature` returns
  /// (10 when there is none).
  ///
  /// A fixed value made every generated tab tie, and the dashboard's sort is
  /// not stable, so tied tabs could swap places between builds. Spacing by 10
  /// leaves room to slot a destination in between by hand.
  static int nextNavDestinationOrder() {
    final orderPattern = RegExp(r'int\s+get\s+order\s*=>\s*(-?\d+)\s*;');
    var highest = -1;
    var found = false;
    final modules = Directory('modules');
    if (!modules.existsSync()) return 10;
    for (final module in modules.listSync().whereType<Directory>()) {
      final lib = Directory('${module.path}/feature/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        if (!RegExp(
          r'(extends|implements)\s+INavDestinationModule\b',
        ).hasMatch(text)) {
          continue;
        }
        for (final match in orderPattern.allMatches(text)) {
          final value = int.parse(match.group(1)!);
          if (!found || value > highest) highest = value;
          found = true;
        }
      }
    }
    return found ? highest + 10 : 10;
  }
}
