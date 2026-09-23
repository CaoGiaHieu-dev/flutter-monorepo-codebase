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
      stdout.writeln('1. Feature Package (modules/<name>/feature/)');
      stdout.writeln('2. Domain Micro-Package (modules/<name>/domain/)');
      stdout.writeln('3. Data Micro-Package (modules/<name>/data/)');
      stdout.writeln('4. Core Package (platform/)');
      stdout.writeln('5. Custom Package (platform/<name>, tiền tố tự chọn)');
      stdout.write('Nhập lựa chọn: ');
      typeInput = stdin.readLineSync()?.trim();
    }

    ModuleType type;
    String typeDir;
    String typeName;

    if (typeInput == '1') {
      type = ModuleType.feature;
      typeDir = 'modules/<name>/feature';
      typeName = 'feature';
    } else if (typeInput == '2') {
      type = ModuleType.domain;
      typeDir = 'modules/<name>/domain';
      typeName = 'domain';
    } else if (typeInput == '3') {
      type = ModuleType.data;
      typeDir = 'modules/<name>/data';
      typeName = 'data';
    } else if (typeInput == '4') {
      type = ModuleType.core;
      typeDir = 'platform';
      typeName = 'core';
    } else if (typeInput == '5') {
      type = ModuleType.custom;
      typeDir = 'platform';
      typeName = '';
    } else {
      stderr.writeln('[ERROR] Lựa chọn không hợp lệ.');
      exit(1);
    }

    if (type == ModuleType.custom) {
      if (args.length < 3) {
        stdout.write('\nNhập tiền tố tên package (ví dụ: analytics, payments): ');
        typeDirInput = stdin.readLineSync()?.trim();
      }
      if (typeDirInput == null || typeDirInput.isEmpty) {
        stderr.writeln('[ERROR] Tên thư mục không được để trống.');
        exit(1);
      }
      // A layer prefix would make arch_check classify a platform package as
      // that layer, and a module layer belongs at modules/<name>/<layer> —
      // types 1-3 build exactly that.
      const reserved = {'feature', 'features', 'domain', 'data', 'core'};
      if (reserved.contains(typeDirInput)) {
        stderr.writeln(
          '[ERROR] "$typeDirInput" là tiền tố của một tầng — dùng loại 1-4.',
        );
        exit(1);
      }
      // A custom package is a platform package with its own name prefix:
      // `<prefix>_<name>` at `platform/<name>`.
      typeName = typeDirInput;
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
          '2. INavDestinationModule — điểm đến chính (CHỈ khi là destination chính của app)',
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
    // A module's layers sit side by side under the module:
    // `modules/<name>/{domain,data,feature}`. Core and custom packages live
    // at `platform/<name>`.
    final isModuleLayer =
        typeInput == '1' || typeInput == '2' || typeInput == '3';
    final modulePath = isModuleLayer
        ? 'modules/$nameInput/$typeName'
        : '$typeDir/$nameInput';
    final moduleDir = Directory(modulePath);

    // Never overwrite: deleting an existing package here would happen before
    // the rollback snapshot, so nothing could restore it.
    if (moduleDir.existsSync()) {
      stderr.writeln(
        '[ERROR] Thư mục "$modulePath" đã tồn tại. '
        'Xoá nó hoặc chọn tên module khác trước khi chạy lại.',
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
