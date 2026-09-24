import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initialize loads package info into the singleton', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Codebase',
      packageName: 'com.example.codebase',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );

    await AppInfoHelper.initialize();

    expect(AppInfoHelper.instance.appName, 'Codebase');
    expect(AppInfoHelper.instance.fullVersion, '1.2.3+45');
  });
}
