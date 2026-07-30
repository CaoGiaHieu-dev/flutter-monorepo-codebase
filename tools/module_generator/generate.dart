import 'dart:io';
import 'package:mustache_template/mustache.dart';

import 'src/common_helpers.dart';
import 'src/input_actions.dart';
import 'src/module_type.dart';
import 'src/pubspec_generator.dart';

void main(List<String> args) async {
  // Đảm bảo script luôn chạy từ thư mục gốc của dự án (workspace root)
  final scriptFile = File(Platform.script.toFilePath());
  final rootDir = scriptFile.parent.parent.parent;
  Directory.current = rootDir;

  stdout.writeln('==========================================');
  stdout.writeln('      Automated Module Generator');
  stdout.writeln('==========================================');

  final inputActions = InputActions();
  final config = inputActions.parseInput(args);

  stdout.writeln(
    '\n[!] Đang khởi tạo module: ${config.moduleName} tại ${config.modulePath}...',
  );

  try {
    // 3. Create Directory Structure
    CommonHelpers.createDir('${config.modulePath}/lib/di');
    CommonHelpers.createDir('${config.modulePath}/lib/src');

    switch (config.type) {
      case ModuleType.feature:
        CommonHelpers.createDir('${config.modulePath}/lib/src/pages');
        CommonHelpers.createDir('${config.modulePath}/lib/src/extensions');
        if (config.smType == StateManagementType.provider) {
          CommonHelpers.createDir('${config.modulePath}/lib/src/providers');
        } else if (config.smType == StateManagementType.bloc) {
          CommonHelpers.createDir('${config.modulePath}/lib/src/blocs');
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
          'pascalName': pascalName,
          'pascalNameInput': pascalNameInput,
          'camelNameInput': camelNameInput,
          'snakeNameInput': snakeName,
          'snakeName': snakeName,
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
              'tools/module_generator/templates/feature/routing/dashboard_tab_module.dart.mustache',
            ).readAsStringSync(),
          );
          File(
            '${config.modulePath}/lib/src/routing/${snakeName}_dashboard_tab_module.dart',
          ).writeAsStringSync(tpl.renderString(routeValues));
        }

        break;
      case ModuleType.domain:
        CommonHelpers.createDir('${config.modulePath}/lib/src/entities');
        CommonHelpers.createDir('${config.modulePath}/lib/src/usecases');
        CommonHelpers.createDir('${config.modulePath}/lib/src/repositories');
        break;
      case ModuleType.data:
        CommonHelpers.createDir('${config.modulePath}/lib/src/models');
        CommonHelpers.createDir(
          '${config.modulePath}/lib/src/repositories_impl',
        );
        CommonHelpers.createDir('${config.modulePath}/lib/src/data_sources');
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

    // 6. Register in Root pubspec.yaml
    stdout.writeln('[!] Đang đăng ký vào root workspace...');
    CommonHelpers.registerInRootWorkspace(config.modulePath);

    // 7. Register in App shell
    stdout.writeln('[!] Đang đăng ký vào app shell...');
    CommonHelpers.registerInAppPubspec(config.moduleName, config.modulePath);
    CommonHelpers.registerInAppInjection(config.moduleName);

    // 8. Run dependency_sync.dart
    stdout.writeln('[!] Đang đồng bộ dependencies với dependency_sync...');
    await CommonHelpers.runCommand('fvm', [
      'dart',
      'tools/dependency_sync.dart',
    ]);

    // 9. Run Toolchain
    stdout.writeln('[!] Đang chạy fvm flutter pub get...');
    await CommonHelpers.runCommand('fvm', ['flutter', 'pub', 'get']);

    if (config.type == ModuleType.feature) {
      stdout.writeln('[!] Đang chạy fvm flutter gen-l10n...');
      await CommonHelpers.runCommand(
        'fvm',
        ['flutter', 'gen-l10n'],
        workingDirectory: config.modulePath,
      );
    }

    stdout.writeln('[!] Đang sinh barrel files...');
    await CommonHelpers.runCommand('fvm', [
      'dart',
      'tools/barrel_generator/generate.dart',
      '${config.modulePath}/lib',
    ]);

    stdout.writeln('[!] Đang chạy build_runner trên workspace...');
    await CommonHelpers.runCommand('fvm', [
      'dart',
      'run',
      'build_runner',
      'build',
      '-d',
      '--workspace',
    ]);

    stdout.writeln('[!] Đang sửa lỗi import với dart fix...');
    await CommonHelpers.runCommand('fvm', [
      'dart',
      'fix',
      '--dry-run',
      'app/lib/di/injection.dart',
    ]);
    await CommonHelpers.runCommand('fvm', [
      'dart',
      'fix',
      '--apply',
    ]);

    stdout.writeln('\n==========================================');
    stdout.writeln('[V] Module "${config.moduleName}" đã được tạo thành công!');
    stdout.writeln('==========================================');
    if (config.type == ModuleType.feature) {
      stdout.writeln('\nCác bước cuối cùng cần thực hiện thủ công:');
      stdout.writeln(
        '1. Hoàn thiện TypedGoRoute / Navigator trong "${config.modulePath}/lib/src/routing/"',
      );
      switch (config.routeContribution) {
        case FeatureRouteContribution.featureRoute:
          stdout.writeln(
            '2. Điền routes vào *FeatureRouteModule (IFeatureRouteModule) — KHÔNG sửa list route trong app_router.dart',
          );
          break;
        case FeatureRouteContribution.dashboardTab:
          stdout.writeln(
            '2. Điền order/path/routes/nav item vào *DashboardTabModule (IDashboardTabModule)',
          );
          stdout.writeln(
            '   ⚠ Chỉ dùng cho tab Bottom Nav chính. Không nhét màn push (login/detail) vào đây.',
          );
          stdout.writeln(
            '   Xem docs/en|vi/08_routing.md mục Dashboard.',
          );
          break;
        case FeatureRouteContribution.none:
          stdout.writeln(
            '2. Nếu cần lộ diện route: đăng ký IFeatureRouteModule hoặc IDashboardTabModule qua DI',
          );
          break;
      }
      stdout.writeln(
        '3. Chạy lại build_runner cho package; hot restart app (DI mới cần full restart)',
      );
      stdout.writeln('==========================================');
    }
  } catch (e) {
    stderr.writeln('[ERROR] Đã xảy ra lỗi: $e');
    exit(1);
  }
}
