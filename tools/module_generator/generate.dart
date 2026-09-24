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

  // Snapshot the shared files so any later failure can be undone.
  CommonHelpers.snapshotSharedFiles(config.modulePath);

  try {
    // 3. Create Directory Structure
    CommonHelpers.createDir('${config.modulePath}/lib/di');
    CommonHelpers.createDir('${config.modulePath}/lib/src');
    // Every package owns its constants in `utils/`, whatever the layer.
    CommonHelpers.createDir('${config.modulePath}/lib/src/utils');

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
      case ModuleType.core:
      case ModuleType.custom:
        break;
    }

    // 4. Create pubspec.yaml
    final pubspecGenerator = PubspecGenerator();
    final pubspecContent = pubspecGenerator.generate(config);
    File('${config.modulePath}/pubspec.yaml').writeAsStringSync(pubspecContent);

    // 4.5. Create .gitignore
    CommonHelpers.generateGitIgnore(config.modulePath);

    // 5. Create lib/di/module.dart
    final diTemplateString = File(
      'tools/module_generator/templates/common/di_module.dart.mustache',
    ).readAsStringSync();
    final diTemplate = Template(diTemplateString);
    File(
      '${config.modulePath}/lib/di/module.dart',
    ).writeAsStringSync(diTemplate.renderString({}));

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

    // Barrels run twice. The templates import sibling barrels
    // (`../pages/pages.dart`), so they must exist before build_runner reads
    // the package; and barrels also export generated files present on disk
    // (`module.module.dart`, `lib/src/gen/**`), so the last run must come
    // after codegen.
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

    stdout.writeln('[!] Fixing imports with dart fix...');
    await CommonHelpers.runDart(
      ['fix', '--apply'],
      workingDirectory: config.modulePath,
    );

    stdout.writeln('\n==========================================');
    stdout.writeln('[V] Module "${config.moduleName}" created.');
    stdout.writeln('==========================================');
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
            '   See docs/{en,vi}/guides/04_routing.md, the Dashboard section.',
          );
          break;
        case FeatureRouteContribution.none:
          stdout.writeln(
            '2. To expose routes later: register an IFeatureRouteModule or INavDestinationModule through DI',
          );
          break;
      }
      stdout.writeln(
        '3. Added a navigator contract to core_di (platform/di/lib/src/navigators/)? '
        'Run "dart tools/barrel_generator/generate.dart platform/di/lib" first',
      );
      stdout.writeln(
        '4. Re-run "dart run build_runner build --workspace", then fully '
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
