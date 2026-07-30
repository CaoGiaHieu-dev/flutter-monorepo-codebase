import 'dart:io';
import 'module_type.dart';

class InputActions {
  ModuleConfig parseInput(List<String> args) {
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
      stdout.writeln('\nChọn loại module muốn tạo:');
      stdout.writeln('1. Feature Package (packages/features/)');
      stdout.writeln('2. Domain Micro-Package (packages/domain/)');
      stdout.writeln('3. Data Micro-Package (packages/data/)');
      stdout.writeln('4. Core Package (packages/core/)');
      stdout.writeln('5. Custom Package (custom name)');
      stdout.write('Nhập lựa chọn: ');
      typeInput = stdin.readLineSync()?.trim();
    }

    ModuleType type;
    String typeDir;
    String typeName;

    if (typeInput == '1') {
      type = ModuleType.feature;
      typeDir = 'packages/features';
      typeName = 'feature';
    } else if (typeInput == '2') {
      type = ModuleType.domain;
      typeDir = 'packages/domain';
      typeName = 'domain';
    } else if (typeInput == '3') {
      type = ModuleType.data;
      typeDir = 'packages/data';
      typeName = 'data';
    } else if (typeInput == '4') {
      type = ModuleType.core;
      typeDir = 'packages/core';
      typeName = 'core';
    } else if (typeInput == '5') {
      type = ModuleType.custom;
      typeDir = 'packages';
      typeName = '';
    } else {
      stderr.writeln('[ERROR] Lựa chọn không hợp lệ.');
      exit(1);
    }

    if (type == ModuleType.custom) {
      if (args.length < 3) {
        stdout.write('\nNhập tên thư mục (ví dụ: features, core, domain): ');
        typeDirInput = stdin.readLineSync()?.trim();
      }
      if (typeDirInput == null || typeDirInput.isEmpty) {
        stderr.writeln('[ERROR] Tên thư mục không được để trống.');
        exit(1);
      }
      typeName = typeDirInput;
      typeDir = 'packages/$typeName';

      if (typeDirInput == 'features') type = ModuleType.feature;
      if (typeDirInput == 'domain') type = ModuleType.domain;
      if (typeDirInput == 'data') type = ModuleType.data;
      if (typeDirInput == 'core') type = ModuleType.core;
    }

    if (args.length < 2) {
      stdout.write('\nNhập tên module con (ví dụ: profile, analytics, core): ');
      nameInput = stdin.readLineSync()?.trim();
    }
    if (nameInput == null || nameInput.isEmpty) {
      stderr.writeln('[ERROR] Tên module không được để trống.');
      exit(1);
    }

    StateManagementType smType = StateManagementType.none;
    FeatureRouteContribution routeContribution =
        FeatureRouteContribution.featureRoute;
    if (type == ModuleType.feature) {
      String smInput = '3';
      if (args.length >= 4) {
        smInput = args[3];
      } else {
        stdout.writeln('\nChọn State Management cho module:');
        stdout.writeln('1. Provider');
        stdout.writeln('2. BLoC');
        stdout.writeln('3. Không sử dụng');
        stdout.write('Nhập lựa chọn (Mặc định 1): ');
        final input = stdin.readLineSync()?.trim();
        if (input != null && input.isNotEmpty) {
          smInput = input;
        } else {
          smInput = '1';
        }
      }

      if (smInput == '1')
        smType = StateManagementType.provider;
      else if (smInput == '2')
        smType = StateManagementType.bloc;

      String routeInput = '1';
      if (args.length >= 5) {
        routeInput = args[4];
      } else if (args.length < 2) {
        stdout.writeln('\nCách gắn route vào App Shell (DI động):');
        stdout.writeln(
          '1. IFeatureRouteModule — màn stack độc lập (auth, onboarding, detail…)',
        );
        stdout.writeln(
          '2. IDashboardTabModule — tab Bottom Nav (CHỈ khi là tab chính của app)',
        );
        stdout.writeln('3. Không scaffold stub route DI');
        stdout.write('Nhập lựa chọn (Mặc định 1): ');
        final input = stdin.readLineSync()?.trim();
        if (input != null && input.isNotEmpty) {
          routeInput = input;
        }
      }

      if (routeInput == '2') {
        routeContribution = FeatureRouteContribution.dashboardTab;
      } else if (routeInput == '3') {
        routeContribution = FeatureRouteContribution.none;
      } else {
        routeContribution = FeatureRouteContribution.featureRoute;
      }
    }

    final moduleName = typeName.isEmpty ? nameInput : '${typeName}_$nameInput';
    final modulePath = '$typeDir/$nameInput';
    final moduleDir = Directory(modulePath);

    if (moduleDir.existsSync()) {
      stderr.writeln('[WARNING] Module "$modulePath" đã tồn tại.');
      stderr.writeln('Bạn có muốn ghi đè không ? (y/n)');

      final confirmInput = stdin.readLineSync()?.trim();
      if (confirmInput == 'y' || confirmInput == 'Y') {
        moduleDir.deleteSync(recursive: true);
      } else {
        exit(1);
      }
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
