import 'dart:io';

import 'package:mustache_template/mustache.dart';

import 'src/common_helpers.dart';
import 'src/input_actions.dart';
import 'src/module_type.dart';
import 'src/pubspec_generator.dart';

void main(List<String> args) async {
  // Always run from the workspace root, wherever the script was started.
  final scriptFile = File(Platform.script.toFilePath());
  final rootDir = scriptFile.parent.parent.parent;
  Directory.current = rootDir;

  if (!args.contains('--help') && !args.contains('-h')) {
    stdout.writeln('==========================================');
    stdout.writeln('      Automated Module Generator');
    stdout.writeln('==========================================');
  }

  final inputActions = InputActions();
  final config = inputActions.parseInput(args);

  // Verify the toolchain BEFORE touching anything shared. Discovering a missing
  // SDK at step 8 used to leave the workspace half-registered.
  try {
    CommonHelpers.assertToolchainAvailable();
  } catch (e) {
    stderr.writeln('[ERROR] $e');
    exit(1);
  }

  if (Directory(config.modulePath).existsSync()) {
    stderr.writeln(
      '[ERROR] Directory "${config.modulePath}" already exists. '
      'Remove it or choose another module name, then run again.',
    );
    exit(1);
  }

  stdout.writeln(
    '\n[!] Creating module ${config.moduleName} at ${config.modulePath}...',
  );

  // An API package is implemented by its module's feature: when that exists
  // (with the route the generator wrote), this run wires it too.
  final isApi = config.type == ModuleType.api;
  final featureToWire = isApi
      ? CommonHelpers.featureToWire(config.nameInput)
      : null;

  // Snapshot the shared files so any later failure can be undone.
  CommonHelpers.snapshotSharedFiles(
    config.modulePath,
    extraFiles: [
      if (featureToWire != null) ...[
        '$featureToWire/pubspec.yaml',
        CommonHelpers.navigatorImplPath(featureToWire, config.nameInput),
      ],
    ],
  );

  try {
    // 3. Create Directory Structure
    CommonHelpers.createDir('${config.modulePath}/lib/src');
    if (!isApi) {
      // An API package has no DI module and owns no constants.
      CommonHelpers.createDir('${config.modulePath}/lib/di');
      // Every other package owns its constants in `utils/`.
      CommonHelpers.createDir('${config.modulePath}/lib/src/utils');
    }

    switch (config.type) {
      case ModuleType.feature:
        CommonHelpers.createDir('${config.modulePath}/lib/src/pages');
        CommonHelpers.createDir('${config.modulePath}/lib/src/extensions');
        if (config.smType == StateManagementType.provider) {
          CommonHelpers.createDir('${config.modulePath}/lib/src/provider');
        } else if (config.smType == StateManagementType.bloc) {
          CommonHelpers.createDir('${config.modulePath}/lib/src/bloc');
        }
        CommonHelpers.createDir('${config.modulePath}/lib/src/routing');
        CommonHelpers.createDir('${config.modulePath}/lib/src/widgets');

        // 3.1 Create assets and localization
        CommonHelpers.createDir('${config.modulePath}/assets/language');
        CommonHelpers.createL10nScaffold(
          config.modulePath,
          config.moduleName,
          config.nameInput,
        );

        // 3.1.1 Scaffold State Management & Page templates
        CommonHelpers.createFeatureTemplates(config);

        // 3.2 Scaffold DI route contribution stub (dynamic AppRouter)
        final pascalName = CommonHelpers.toPascalCase(config.moduleName);
        final pascalNameInput = CommonHelpers.toPascalCase(config.nameInput);
        final camelNameInput = CommonHelpers.toCamelCase(config.nameInput);
        final snakeName = config.nameInput;

        final routeValues = {
          'moduleName': config.moduleName,
          'pascalName': pascalName,
          'pascalNameInput': pascalNameInput,
          'camelNameInput': camelNameInput,
          'snakeNameInput': snakeName,
          'snakeName': snakeName,
          'screamingNameInput': CommonHelpers.toScreamingSnakeCase(snakeName),
          if (config.routeContribution == FeatureRouteContribution.dashboardTab)
            'navOrder': CommonHelpers.nextNavDestinationOrder(),
        };

        if (config.routeContribution == FeatureRouteContribution.featureRoute) {
          final tpl = Template(
            File(
              'tools/module_generator/templates/feature/routing/feature_route_module.dart.mustache',
            ).readAsStringSync(),
          );
          File(
            '${config.modulePath}/lib/src/routing/${snakeName}_feature_route_module.dart',
          ).writeAsStringSync(tpl.renderString(routeValues));
        } else if (config.routeContribution ==
            FeatureRouteContribution.dashboardTab) {
          final tpl = Template(
            File(
              'tools/module_generator/templates/feature/routing/nav_destination.dart.mustache',
            ).readAsStringSync(),
          );
          File(
            '${config.modulePath}/lib/src/routing/${snakeName}_nav_destination.dart',
          ).writeAsStringSync(tpl.renderString(routeValues));
        }

        break;
      case ModuleType.domain:
        CommonHelpers.createDir('${config.modulePath}/lib/src/entities');
        CommonHelpers.createDir('${config.modulePath}/lib/src/usecases');
        CommonHelpers.createDir('${config.modulePath}/lib/src/repositories');
        CommonHelpers.createDomainTemplates(config);
        break;
      case ModuleType.data:
        CommonHelpers.createDir('${config.modulePath}/lib/src/models');
        CommonHelpers.createDir(
          '${config.modulePath}/lib/src/repositories_impl',
        );
        CommonHelpers.createDir('${config.modulePath}/lib/src/data_sources');
        CommonHelpers.createDataTemplates(
          config,
          hasDomain: PubspecGenerator.hasDomainPackage(config),
        );
        break;
      case ModuleType.api:
        CommonHelpers.createDir('${config.modulePath}/lib/src/navigators');
        CommonHelpers.createApiTemplates(config);
        if (featureToWire != null) {
          CommonHelpers.wireFeatureToApi(featureToWire, config.nameInput);
        }
        break;
      case ModuleType.core:
      case ModuleType.custom:
        break;
    }

    // 4. Create pubspec.yaml
    final pubspecGenerator = PubspecGenerator();
    final pubspecContent = pubspecGenerator.generate(config);
    File('${config.modulePath}/pubspec.yaml').writeAsStringSync(pubspecContent);

    // No per-package .gitignore: the root one covers build output and
    // generated code at any depth.

    // 5. Create lib/di/module.dart (not for an API package: no DI)
    if (!isApi) {
      final diTemplateString = File(
        'tools/module_generator/templates/common/di_module.dart.mustache',
      ).readAsStringSync();
      final diTemplate = Template(diTemplateString);
      File(
        '${config.modulePath}/lib/di/module.dart',
      ).writeAsStringSync(diTemplate.renderString({}));
    }

    // 6. Register in every app manifest (or only those `--apps` names) —
    // the only hand-edited composition input.
    stdout.writeln('[!] Registering in app_manifest.yaml...');
    CommonHelpers.registerInAppManifests(
      config.moduleName,
      config.type,
      config.nameInput,
      apps: config.apps,
    );

    // 7. Regenerate what the manifests drive: the root `workspace:` list, each
    // app's path dependencies and `injection.dart`, all between
    // `composer:managed` markers. Writing any of them by hand would leave an
    // entry outside the markers that composer never removes.
    stdout.writeln('[!] Running composer sync...');
    await CommonHelpers.runDart(['tools/composer/composer.dart', 'sync']);

    // 8. Run dependency_sync.dart
    stdout.writeln('[!] Syncing dependency versions (dependency_sync)...');
    await CommonHelpers.runDart(['tools/dependency_sync.dart']);

    // 9. Run Toolchain
    stdout.writeln('[!] Running flutter pub get...');
    CommonHelpers.noteWorkspaceResolving();
    await CommonHelpers.runFlutter(['pub', 'get']);

    if (config.type == ModuleType.feature) {
      stdout.writeln('[!] Running flutter gen-l10n...');
      await CommonHelpers.runFlutter(
        ['gen-l10n'],
        workingDirectory: config.modulePath,
      );
    }

    // The package barrel is written twice: once so the package has its
    // public entry point while build_runner reads it, and again after
    // codegen, because it also exports generated files present on disk
    // (`module.module.dart`, `lib/src/gen/**`).
    stdout.writeln('[!] Generating barrel files...');
    await CommonHelpers.runDart([
      'tools/barrel_generator/generate.dart',
      '${config.modulePath}/lib',
    ]);

    stdout.writeln('[!] Running build_runner on the workspace...');
    CommonHelpers.noteCodegenStarted();
    await CommonHelpers.runDart([
      'run',
      'build_runner',
      'build',
      '--workspace',
    ]);

    stdout.writeln('[!] Regenerating barrel files after codegen...');
    await CommonHelpers.runDart([
      'tools/barrel_generator/generate.dart',
      '${config.modulePath}/lib',
    ]);
    if (featureToWire != null) {
      // Its new navigator implementation joins the feature's barrel.
      await CommonHelpers.runDart([
        'tools/barrel_generator/generate.dart',
        '$featureToWire/lib',
      ]);
    }

    stdout.writeln('[!] Fixing imports with dart fix...');
    await CommonHelpers.runDart(
      ['fix', '--apply'],
      workingDirectory: config.modulePath,
    );

    stdout.writeln('\n==========================================');
    stdout.writeln('[V] Module "${config.moduleName}" created.');
    stdout.writeln('==========================================');
    if (isApi) {
      final pascal = CommonHelpers.toPascalCase(config.nameInput);
      stdout.writeln('\nWhat is left for you to do by hand:');
      stdout.writeln(
        '1. Shape ${pascal}Navigator in "${config.modulePath}/lib/src/navigators/" '
        '(add action handlers under lib/src/actions/ the same way), then run '
        '"dart tools/barrel_generator/generate.dart ${config.modulePath}/lib"',
      );
      stdout.writeln(
        featureToWire != null
            ? '2. feature_${config.nameInput} implements it in '
                  '${CommonHelpers.navigatorImplPath(featureToWire, config.nameInput)} — '
                  'keep the two in step'
            : '2. Implement it in feature_${config.nameInput}: generate the '
                  'feature now and it is wired for you, or add '
                  '"${config.moduleName}" to an existing feature\'s pubspec and a '
                  '@LazySingleton(as: ${pascal}Navigator) in its routing/',
      );
      stdout.writeln(
        '3. A feature that navigates here declares "${config.moduleName}" and '
        'resolves getItOrNull<${pascal}Navigator>() (RULE-22, arch_check R8)',
      );
      stdout.writeln('==========================================');
    }
    if (config.type == ModuleType.feature) {
      stdout.writeln('\nWhat is left for you to do by hand:');
      stdout.writeln(
        '1. Fill in the TypedGoRoute / navigator in "${config.modulePath}/lib/src/routing/"',
      );
      switch (config.routeContribution) {
        case FeatureRouteContribution.featureRoute:
          stdout.writeln(
            '2. Populate routes in the *FeatureRouteModule (IFeatureRouteModule) — do NOT edit the route list in app_router.dart',
          );
          break;
        case FeatureRouteContribution.dashboardTab:
          stdout.writeln(
            '2. Populate order/path/routes/destination in the *NavDestination (INavDestinationModule)',
          );
          stdout.writeln(
            '   ⚠ For a primary bottom-nav tab only. Pushed screens (login/detail) do not belong here.',
          );
          stdout.writeln(
            '   See docs/en/guides/04_routing.md § 1 (Pick the routing contract).',
          );
          break;
        case FeatureRouteContribution.none:
          stdout.writeln(
            '2. To expose routes later: register an IFeatureRouteModule or INavDestinationModule through DI',
          );
          break;
      }
      stdout.writeln(
        PubspecGenerator.hasApiPackage(config)
            ? '3. Other modules navigate here through ${config.nameInput}_api: '
                  'lib/src/routing/${config.nameInput}_navigator_impl.dart '
                  'implements its navigator'
            : '3. Other modules navigate here through a navigator in this '
                  'module\'s API package: "dart tools/module_generator/generate.dart '
                  '6 ${config.nameInput}" creates it and implements it here',
      );
      stdout.writeln(
        '4. Translate "${config.modulePath}/assets/language/vi.arb" — it '
        'starts as a copy of the English text',
      );
      stdout.writeln(
        '5. Re-run "dart run build_runner build --workspace", then fully '
        'restart the app — hot reload does not pick up new DI registrations',
      );
      stdout.writeln('==========================================');
    }
  } catch (e) {
    stderr.writeln('[ERROR] Unexpected error: $e');
    await CommonHelpers.rollback();
    exit(1);
  }
}
