import 'dart:io';

/// CLI Tool to generate a compliant "Stub / Placeholder Package" for a feature module.
///
/// Usage:
///   dart tools/stub_generator/generate_stub.dart <feature_name>
/// Example:
///   dart tools/stub_generator/generate_stub.dart order
void main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('❌ Error: Feature name is required.');
    stdout.writeln(
      'Usage: dart tools/stub_generator/generate_stub.dart <feature_name>',
    );
    exit(1);
  }

  final rawName = args.first.toLowerCase().replaceAll('feature_', '');
  final packageName = 'feature_$rawName';
  final classNamePrefix = _pascalCase(rawName);
  final targetDir = Directory('packages/features/$rawName');

  if (targetDir.existsSync()) {
    stdout.writeln(
      '⚠️ Warning: Directory ${targetDir.path} already exists. Aborting.',
    );
    exit(1);
  }

  stdout.writeln(
    '🚀 Generating Stub Package for: $packageName at ${targetDir.path} ...',
  );

  // 1. Create directory structure
  final libDir = Directory('${targetDir.path}/lib');
  final srcPresentationDir = Directory('${libDir.path}/src/presentation');
  final srcRoutingDir = Directory('${libDir.path}/src/routing');
  final diDir = Directory('${libDir.path}/di');

  srcPresentationDir.createSync(recursive: true);
  srcRoutingDir.createSync(recursive: true);
  diDir.createSync(recursive: true);

  // 2. Write pubspec.yaml
  final pubspecContent = '''

name: $packageName
description: "$classNamePrefix presentation feature package (Stub / Submodule Placeholder)"
version: 1.0.0
publish_to: none

environment:
  sdk: ">=3.13.3 <4.0.0"
  flutter: ">=3.47.4"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  material_ui: ^1.1.1
  go_router: "^18.0.0"
  get_it: ^9.2.1
  injectable: ^3.0.0
  core_di:
    path: ../../core/di
  core_ui_kit:
    path: ../../core/ui_kit
  core_base_ui:
    path: ../../core/base_ui

dev_dependencies:
  build_runner: "^2.16.0"
  injectable_generator: "^3.1.3"
''';
  File('${targetDir.path}/pubspec.yaml').writeAsStringSync(pubspecContent);

  // 3. Write Presentation Stub Page
  final pageContent = '''

import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ${classNamePrefix}StubPage extends StatelessWidget {
  const ${classNamePrefix}StubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('$classNamePrefix Module (Stub)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: StubFeatureWidget(
          featureName: '$classNamePrefix Module',
          submoduleRepoUrl: 'git@github.com:company/${packageName}_private.git',
          description: 'Mã nguồn $classNamePrefix thuộc quyền sở hữu của team chuyên trách.\\nApp Shell đang chạy với Mock Contract để hỗ trợ test độc lập.',
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mock action in $classNamePrefix triggered!'),
                    backgroundColor: Colors.green,
                  ),
                );
                context.pop();
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Simulate Action (Mock)'),
            ),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back to App'),
            ),
          ],
        ),
      ),
    );
  }
}
''';
  File(
    '${srcPresentationDir.path}/${rawName}_stub_page.dart',
  ).writeAsStringSync(pageContent);

  // 4. Write Route Module
  final routeContent = '''

import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../presentation/${rawName}_stub_page.dart';

@LazySingleton(as: IFeatureRouteModule)
class ${classNamePrefix}RouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [
        GoRoute(
          path: '/$rawName',
          parentNavigatorKey: NavigatorKeys.rootKey,
          builder: (context, state) => const ${classNamePrefix}StubPage(),
        ),
      ];
}
''';
  File(
    '${srcRoutingDir.path}/${rawName}_route_module.dart',
  ).writeAsStringSync(routeContent);

  // 5. Write Navigator Impl
  final navigatorImplContent = '''

import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ${classNamePrefix}Navigator)
class ${classNamePrefix}NavigatorImpl implements ${classNamePrefix}Navigator {
  @override
  void to$classNamePrefix(BuildContext context) {
    context.push('/$rawName');
  }
}
''';
  File(
    '${srcRoutingDir.path}/${rawName}_navigator_impl.dart',
  ).writeAsStringSync(navigatorImplContent);

  // 6. Write di/module.dart
  final diContent = '''

import 'package:injectable/injectable.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}
''';
  File('${diDir.path}/module.dart').writeAsStringSync(diContent);

  // 7. Write barrel file
  final barrelContent = '''

library $packageName;

export 'di/module.module.dart';
export 'src/presentation/${rawName}_stub_page.dart';
export 'src/routing/${rawName}_navigator_impl.dart';
export 'src/routing/${rawName}_route_module.dart';
''';
  File('${libDir.path}/$packageName.dart').writeAsStringSync(barrelContent);

  // 8. Write Navigator Interface in core_di
  final navigatorInterfaceFile = File(
    'packages/core/di/lib/src/navigators/${rawName}_navigator.dart',
  );
  if (!navigatorInterfaceFile.existsSync()) {
    navigatorInterfaceFile.writeAsStringSync('''

import 'package:flutter/widgets.dart';

abstract class ${classNamePrefix}Navigator {
  void to$classNamePrefix(BuildContext context);
}
''');
    stdout.writeln(
      '  + Created core_di contract: ${navigatorInterfaceFile.path}',
    );
  }

  stdout.writeln('✅ Stub Package $packageName created successfully!');
  stdout.writeln('👉 Next steps:');
  stdout.writeln(
    '  1. Add "  - packages/features/$rawName" to root pubspec.yaml workspace:',
  );
  stdout.writeln('  2. Add "$packageName:" to apps/mobile/pubspec.yaml');
  stdout.writeln(
    '  3. Register "ExternalModule(Feature${classNamePrefix}PackageModule)" in apps/mobile/lib/di/injection.dart',
  );
  stdout.writeln('  4. Run `flutter pub get` and `dart run build_runner build -d`');
}

String _pascalCase(String text) {
  return text
      .split('_')
      .map(
        (part) =>
            part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1),
      )
      .join('');
}
