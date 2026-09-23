import 'dart:io';

import 'package:mustache_template/mustache.dart';

import '../../shared/toolchain.dart' as toolchain;
import 'module_type.dart';

class CommonHelpers {
  static void createDir(String path) {
    Directory(path).createSync(recursive: true);
    stdout.writeln('  -> Đã tạo thư mục: $path');
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
      stdout.writeln('[INFO] Phát hiện cấu hình FVM. Dùng "fvm dart/flutter".');
      return;
    }

    for (final executable in const ['dart', 'flutter']) {
      try {
        final result = Process.runSync(executable, [
          '--version',
        ], runInShell: true);
        if (result.exitCode != 0) {
          throw Exception('"$executable --version" trả về ${result.exitCode}');
        }
      } on ProcessException {
        throw Exception(
          'Không tìm thấy "$executable" trong PATH và cũng không có FVM khả dụng. '
          'Cài Flutter SDK hoặc chạy "dart pub global activate fvm" trước khi tạo module.',
        );
      }
    }
    stdout.writeln('[INFO] Không dùng FVM. Dùng "dart/flutter" toàn cục.');
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
  /// app's `app_manifest.yaml` ([registerInAppManifests]), and what
  /// `composer sync` regenerates from them — the root `pubspec.yaml`, each
  /// app's `pubspec.yaml` and `lib/di/injection.dart`.
  ///
  /// A failure partway through would leave these half-edited — a module
  /// registered in the workspace whose directory was never finished building,
  /// which then breaks `pub get` for everyone. Hence the backup-and-restore
  /// around them.
  static List<String> get sharedMutatedFiles => [
    'pubspec.yaml',
    for (final manifest in _findManifests(Directory('.'))) ...[
      manifest.path,
      '${manifest.parent.path}/pubspec.yaml',
      '${manifest.parent.path}/lib/di/injection.dart',
    ],
  ];

  static final Map<String, String?> _sharedFileSnapshots = {};
  static String? _createdModulePath;

  /// Snapshots every shared file before the first mutation.
  ///
  /// A `null` value records "did not exist", so restore deletes rather than
  /// resurrecting a file generation created.
  static void snapshotSharedFiles(String modulePath) {
    _createdModulePath = modulePath;
    _sharedFileSnapshots.clear();
    for (final path in sharedMutatedFiles) {
      final file = File(path);
      _sharedFileSnapshots[path] = file.existsSync()
          ? file.readAsStringSync()
          : null;
    }
  }

  /// Restores the snapshotted files and removes the half-built module.
  ///
  /// Best-effort by design: it reports what it could not undo instead of
  /// throwing, because it runs while another error is already propagating.
  static void rollback() {
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

    if (failures.isEmpty) {
      stderr.writeln(
        '[ROLLBACK] Đã hoàn tác mọi thay đổi. Workspace trở lại nguyên trạng.',
      );
      return;
    }

    stderr.writeln('[ROLLBACK] Không hoàn tác được các mục sau — cần dọn tay:');
    for (final failure in failures) {
      stderr.writeln('  - $failure');
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

  /// Adds the new module to every app manifest, then leaves the wiring alone.
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
  static void registerInAppManifests(
    String packageName,
    ModuleType moduleType,
    String moduleName,
  ) {
    final manifests = _findManifests(Directory('.'));
    if (manifests.isEmpty) {
      stdout.writeln(
        '  !! Không tìm thấy app_manifest.yaml — bỏ qua bước ghép vào app.',
      );
      return;
    }

    // `feature` / `domain` / `data` are layers of a module; a core or custom
    // package is a platform package that joins a DI group directly.
    final layer = switch (moduleType) {
      ModuleType.feature => 'feature',
      ModuleType.domain => 'domain',
      ModuleType.data => 'data',
      ModuleType.core || ModuleType.custom => null,
    };

    for (final manifest in manifests) {
      final lines = manifest.readAsLinesSync();
      if (lines.any((l) => l.contains(packageName))) continue;

      if (layer != null) {
        _addModuleLayer(lines, moduleName, layer);
      } else {
        _addPlatformPackage(lines, packageName);
      }
      manifest.writeAsStringSync('${lines.join('\n')}\n');
      stdout.writeln('  -> Đã thêm vào ${manifest.path}');
    }
  }

  /// `- { id: <name>, layers: [...] }` — appended, or extended if present.
  static void _addModuleLayer(
    List<String> lines,
    String moduleName,
    String layer,
  ) {
    final existing = lines.indexWhere(
      (l) => l.trimLeft().startsWith('- { id: $moduleName,'),
    );
    if (existing != -1) {
      final layers =
          RegExp(r'layers:\s*\[([^\]]*)\]')
              .firstMatch(lines[existing])
              ?.group(1)
              ?.split(',')
              .map((l) => l.trim())
              .toSet() ??
          const <String>{};
      if (!layers.contains(layer)) {
        lines[existing] = lines[existing].replaceFirst(
          'layers: [',
          'layers: [$layer, ',
        );
      }
      return;
    }
    final modulesIndex = lines.indexWhere((l) => l.trimRight() == 'modules:');
    if (modulesIndex == -1) return;
    var insertAt = modulesIndex + 1;
    while (insertAt < lines.length &&
        lines[insertAt].trimLeft().startsWith('- ')) {
      insertAt++;
    }
    lines.insert(insertAt, '  - { id: $moduleName, layers: [$layer] }');
  }

  /// A platform package joins the `core` DI group, or `extra_dependencies`
  /// when it ships no `@InjectableInit.microPackage()`.
  static void _addPlatformPackage(List<String> lines, String packageName) {
    final anchor = lines.indexWhere((l) => l.trimRight() == '    packages:');
    if (anchor == -1) return;
    var insertAt = anchor + 1;
    while (insertAt < lines.length &&
        lines[insertAt].trimLeft().startsWith('- ')) {
      insertAt++;
    }
    lines.insert(insertAt, '      - $packageName');
  }

  static List<File> _findManifests(Directory dir) {
    final out = <File>[];
    const skip = {'.git', '.dart_tool', 'build', 'packages', 'modules'};
    void walk(Directory d) {
      for (final e in d.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory) {
          if (skip.contains(name) || name.startsWith('.')) continue;
          walk(e);
        } else if (e is File && name == 'app_manifest.yaml') {
          out.add(e);
        }
      }
    }

    walk(dir);
    return out;
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

  /// `user_profile` -> `USER_PROFILE`, matching the repo's constant style.
  static String toScreamingSnakeCase(String snakeCase) {
    return snakeCase.toUpperCase();
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

    stdout.writeln(
      '  -> Đã tạo template mã nguồn cho ${config.smType.name.toUpperCase()}, Route và Page',
    );
  }
}
