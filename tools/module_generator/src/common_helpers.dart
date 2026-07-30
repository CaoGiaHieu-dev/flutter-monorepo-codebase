import 'dart:io';
import 'package:mustache_template/mustache.dart';
import 'module_type.dart';

class CommonHelpers {

  static void createDir(String path) {
    Directory(path).createSync(recursive: true);
    stdout.writeln('  -> Đã tạo thư mục: $path');
  }

  static void registerInRootWorkspace(String path) {
    final rootPubspec = File('pubspec.yaml');
    if (!rootPubspec.existsSync()) return;

    final lines = rootPubspec.readAsLinesSync();
    final workspaceIndex = lines.indexWhere(
      (line) => line.trim() == 'workspace:',
    );

    if (workspaceIndex != -1) {
      final normalizedPath = path.replaceAll('\\\\', '/');
      if (lines.any((line) => line.contains(normalizedPath))) {
        stdout.writeln('  (Module đã được đăng ký trong workspace)');
        return;
      }

      int insertIndex = workspaceIndex + 1;
      while (insertIndex < lines.length &&
          lines[insertIndex].trim().startsWith('-')) {
        insertIndex++;
      }
      lines.insert(insertIndex, '  - $normalizedPath');
      rootPubspec.writeAsStringSync('${lines.join('\n')}\n');
      stdout.writeln('  -> Đã đăng ký module vào root pubspec.yaml');
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

  static void generateGitIgnore(String modulePath) {
    final templateString = File(
      'tools/module_generator/templates/common/gitignore.mustache',
    ).readAsStringSync();
    final template = Template(templateString);
    final content = template.renderString({});
    File('$modulePath/.gitignore').writeAsStringSync(content);
  }

  static void registerInAppPubspec(String moduleName, String modulePath) {
    final appPubspec = File('app/pubspec.yaml');
    if (!appPubspec.existsSync()) return;

    final lines = appPubspec.readAsLinesSync();
    if (lines.any((line) => line.trim().startsWith('$moduleName:'))) return;

    final insertIndex = lines.indexWhere(
      (line) => line.contains('# external packages'),
    );
    if (insertIndex != -1) {
      lines.insert(insertIndex, '  $moduleName:\n    path: ../$modulePath');
      appPubspec.writeAsStringSync('${lines.join('\n')}\n');
      stdout.writeln('  -> Đã thêm $moduleName vào app/pubspec.yaml');
    }
  }

  static void registerInAppInjection(String moduleName) {
    final file = File('app/lib/di/injection.dart');
    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();
    final pascalName = toPascalCase(moduleName);

    if (lines.any((line) => line.contains('${pascalName}PackageModule')))
      return;

    final importLine = "import 'package:$moduleName/di/module.module.dart';";
    final lastPackageImportIndex = lines.lastIndexWhere(
      (line) => line.startsWith("import 'package:"),
    );
    if (lastPackageImportIndex != -1) {
      lines.insert(lastPackageImportIndex + 1, importLine);
    } else {
      lines.insert(0, importLine);
    }

    String targetListName = '_otherModules';
    if (moduleName.startsWith('feature_'))
      targetListName = '_featureModules';
    else if (moduleName.startsWith('domain_'))
      targetListName = '_domainModules';
    else if (moduleName.startsWith('data_'))
      targetListName = '_dataModules';
    else if (moduleName.startsWith('core_'))
      targetListName = '_coreModules';

    final listStartIndex = lines.indexWhere(
      (line) => line.contains('const $targetListName = ['),
    );

    if (listStartIndex != -1) {
      int insertIndex = listStartIndex + 1;
      while (insertIndex < lines.length && !lines[insertIndex].contains('];')) {
        insertIndex++;
      }
      lines.insert(
        insertIndex,
        '  ExternalModule(${pascalName}PackageModule),',
      );
    } else {
      final initIndex = lines.indexWhere(
        (line) => line.contains('@InjectableInit('),
      );
      if (initIndex != -1) {
        lines.insertAll(initIndex, [
          'const $targetListName = [',
          '  ExternalModule(${pascalName}PackageModule),',
          '];',
          '',
        ]);

        final externalIndex = lines.indexWhere(
          (line) => line.contains('externalPackageModulesBefore: ['),
          initIndex,
        );
        if (externalIndex != -1) {
          lines.insert(externalIndex + 1, '    ...$targetListName,');
        }
      }
    }

    file.writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln(
      '  -> Đã đăng ký ${pascalName}PackageModule vào app/lib/di/injection.dart ($targetListName)',
    );
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

    // di/localization.dart
    final diLocTemplate = Template(
      File(
        'tools/module_generator/templates/feature/localization/localization.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '$modulePath/lib/di/localization.dart',
    ).writeAsStringSync(diLocTemplate.renderString(values));

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
      '  -> Đã tạo l10n.yaml, các file .arb, extension và DI cho localization',
    );
  }

  static String toCamelCase(String snakeCase) {
    final pascal = toPascalCase(snakeCase);
    if (pascal.isEmpty) return '';
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

  static void createFeatureTemplates(ModuleConfig config) {
    final pascalNameInput = toPascalCase(config.nameInput);
    final camelNameInput = toCamelCase(config.nameInput);
    final snakeNameInput = config.nameInput;

    final values = {
      'moduleName': config.moduleName,
      'pascalName': toPascalCase(config.moduleName),
      'pascalNameInput': pascalNameInput,
      'camelNameInput': camelNameInput,
      'snakeNameInput': snakeNameInput,
      'snakeName': snakeNameInput,
      'isProvider': config.smType == StateManagementType.provider,
      'isBloc': config.smType == StateManagementType.bloc,
      'isNone': config.smType == StateManagementType.none,
    };

    String pageTemplatePath;
    if (config.smType == StateManagementType.provider) {
      pageTemplatePath =
          'tools/module_generator/templates/feature/provider/page.dart.mustache';

      final providerTpl = Template(
        File(
          'tools/module_generator/templates/feature/provider/provider.dart.mustache',
        ).readAsStringSync(),
      );
      File(
        '${config.modulePath}/lib/src/providers/${snakeNameInput}_provider.dart',
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

      CommonHelpers.createDir(
        '${config.modulePath}/lib/src/blocs/$snakeNameInput',
      );
      File(
        '${config.modulePath}/lib/src/blocs/$snakeNameInput/${snakeNameInput}_bloc.dart',
      ).writeAsStringSync(blocTpl.renderString(values));
      File(
        '${config.modulePath}/lib/src/blocs/$snakeNameInput/${snakeNameInput}_event.dart',
      ).writeAsStringSync(eventTpl.renderString(values));
      File(
        '${config.modulePath}/lib/src/blocs/$snakeNameInput/${snakeNameInput}_state.dart',
      ).writeAsStringSync(stateTpl.renderString(values));
    } else {
      pageTemplatePath =
          'tools/module_generator/templates/feature/default/page.dart.mustache';
    }

    final pageTpl = Template(File(pageTemplatePath).readAsStringSync());
    File(
      '${config.modulePath}/lib/src/pages/${snakeNameInput}_page.dart',
    ).writeAsStringSync(pageTpl.renderString(values));

    // 2. Create routing path and route_module files
    final pathTpl = Template(
      File(
        'tools/module_generator/templates/feature/routing/path.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/routing/${snakeNameInput}_path.dart',
    ).writeAsStringSync(pathTpl.renderString(values));

    final routeModuleTpl = Template(
      File(
        'tools/module_generator/templates/feature/routing/route_module.dart.mustache',
      ).readAsStringSync(),
    );
    File(
      '${config.modulePath}/lib/src/routing/${snakeNameInput}_route_module.dart',
    ).writeAsStringSync(routeModuleTpl.renderString(values));

    stdout.writeln(
      '  -> Đã tạo template mã nguồn cho ${config.smType.name.toUpperCase()}, Route và Page',
    );
  }



  static void registerLocalizationsDelegateInApp(String moduleName) {
    // Không còn cần thiết, GetIt getAll đã đảm nhận.
    final file = File('app/lib/presentation/root_app.dart');
    if (!file.existsSync()) return;

    final lines = file.readAsLinesSync();
    final pascalName = toPascalCase(moduleName);
    final delegateClass = 'Feature${pascalName}Localizations';

    if (lines.any((line) => line.contains('$delegateClass.delegate'))) return;

    final importLine =
        "import 'package:$moduleName/src/l10n/generated/app_localizations_$moduleName.dart';";

    // 1. Add import if not exists
    final lastImportIndex = lines.lastIndexWhere(
      (line) => line.startsWith('import '),
    );
    if (lastImportIndex != -1) {
      if (!lines.any((l) => l.trim() == importLine)) {
        lines.insert(lastImportIndex + 1, importLine);
      }
    }

    // 2. Add delegate to localizationsDelegates list
    final delegateListIndex = lines.indexWhere(
      (line) => line.contains('localizationsDelegates: ['),
    );
    if (delegateListIndex != -1) {
      int insertIndex = delegateListIndex + 1;
      lines.insert(insertIndex, '        $delegateClass.delegate,');
    } else {
      // try multiline format if single line doesn't match
      final delegateIndex = lines.indexWhere(
        (line) => line.contains('localizationsDelegates:'),
      );
      if (delegateIndex != -1) {
        lines.insert(delegateIndex + 1, '        $delegateClass.delegate,');
      }
    }

    file.writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln(
      '  -> Đã đăng ký $delegateClass.delegate vào app/lib/presentation/root_app.dart',
    );
  }
}
