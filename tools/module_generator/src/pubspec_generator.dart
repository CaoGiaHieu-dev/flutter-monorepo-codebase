import 'dart:io';
import 'package:mustache_template/mustache.dart';
import 'common_helpers.dart';
import 'module_type.dart';

class PubspecGenerator {
  String generate(ModuleConfig config) {
    final templateString = File(
      'tools/module_generator/templates/common/pubspec.yaml.mustache',
    ).readAsStringSync();
    final template = Template(templateString);
    final pascalName = CommonHelpers.toPascalCase(config.moduleName);

    final values = {
      'moduleName': config.moduleName,
      'moduleAssetName': pascalName,
      'isFeature': config.type == ModuleType.feature,
      'isDomain': config.type == ModuleType.domain,
      'isData': config.type == ModuleType.data,
      'isCore': config.type == ModuleType.core,
      'isCustom': config.type == ModuleType.custom,
      'isCoreOrCustom':
          config.type == ModuleType.core || config.type == ModuleType.custom,
      'isProvider': config.smType == StateManagementType.provider,
      'isBloc': config.smType == StateManagementType.bloc,
    };

    return template.renderString(values);
  }
}
