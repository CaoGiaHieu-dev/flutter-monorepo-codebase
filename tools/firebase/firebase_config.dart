import 'dart:io';

void main() async {
  stdout.writeln('==========================================');
  stdout.writeln('    FlutterFire Config Setup Script');
  stdout.writeln('==========================================');

  // Check if running from root
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln(
      '[X] Error: Please run this script from the project root directory.',
    );
    stderr.writeln('Current directory: ${Directory.current.path}');
    exit(1);
  }

  // Detect FVM: Only use it if .fvm/fvm_config.json exists
  final hasFvmConfig = File('.fvm/fvm_config.json').existsSync();
  final dartCmd = hasFvmConfig ? 'fvm' : 'dart';
  final dartArgs = hasFvmConfig ? ['dart'] : <String>[];

  if (hasFvmConfig) {
    stdout.writeln('[INFO] Detected FVM config. Using FVM CLI.');
  } else {
    stdout.writeln(
      '[INFO] FVM config not detected. Using global Flutter/Dart SDK.',
    );
  }

  // 1. Check if Firebase CLI is installed
  if (!_isCommandAvailable('firebase')) {
    stdout.writeln('[!] Firebase CLI not found. Installing via npm...');
    await _runCommand('npm', ['install', '-g', 'firebase-tools']);
  }

  // Check login status
  stdout.writeln('Checking Firebase login status...');
  while (true) {
    final loginCheck = await Process.run('firebase', [
      'projects:list',
    ], runInShell: true);
    if (loginCheck.exitCode == 0) {
      break;
    }
    stdout.writeln(
      '[!] Firebase is not logged in or session expired. Running \'firebase login\'...',
    );
    await _runCommand('firebase', ['login']);
  }
  stdout.writeln('[V] Firebase logged in.');

  // 2. Check if FlutterFire CLI is installed
  if (!_isCommandAvailable('flutterfire')) {
    stdout.writeln('[!] FlutterFire CLI not found. Installing...');
    await _runCommand(dartCmd, [
      ...dartArgs,
      'pub',
      'global',
      'activate',
      'flutterfire_cli',
    ]);

    // After activation, we might need to check again or inform the user about PATH
    if (!_isCommandAvailable('flutterfire')) {
      stderr.writeln(
        '[X] FlutterFire CLI installed but \'flutterfire\' command not found in PATH.',
      );
      stderr.writeln(
        'Please ensure your Dart pub cache bin directory is in your system PATH.',
      );
      exit(1);
    }
  }
  stdout.writeln('[V] FlutterFire CLI ready.');

  // 3. Gather user inputs
  final projectId = _prompt(
    'Enter Firebase Project ID (e.g. codebase-provider): ',
  );
  if (projectId.isEmpty) {
    stderr.writeln('Project ID cannot be empty.');
    exit(1);
  }

  final baseBundleId = _prompt(
    'Enter Base Bundle ID / Package Name (e.g. com.example.codebase): ',
  );
  if (baseBundleId.isEmpty) {
    stderr.writeln('Base Bundle ID cannot be empty.');
    exit(1);
  }

  final inputFlavors = _prompt(
    'Enter Flavors separated by space (default: dev staging prod): ',
  );
  final flavors = inputFlavors.isEmpty
      ? ['dev', 'staging', 'prod']
      : inputFlavors.split(' ').where((s) => s.isNotEmpty).toList();

  // 4. Run configurations
  stdout.writeln('==========================================');
  stdout.writeln(
    'Running FlutterFire config for flavors: ${flavors.join(' ')}',
  );
  stdout.writeln('==========================================');

  for (final flavor in flavors) {
    stdout.writeln('----------------------------------------');
    stdout.writeln('Configuring $flavor environment...');
    stdout.writeln('----------------------------------------');

    final bundleId = (flavor == 'prod' || flavor == 'production')
        ? baseBundleId
        : '$baseBundleId.$flavor';

    for (final buildMode in ['Debug', 'Profile', 'Release']) {
      stdout.writeln('=> Setting up $buildMode-$flavor');
      await _runCommand('flutterfire', [
        'config',
        '--yes',
        '--project=$projectId',
        '--out=../packages/core/common/lib/src/firebase/firebase_options_$flavor.dart',
        '--ios-bundle-id=$bundleId',
        '--ios-out=ios/flavors/$flavor/GoogleService-Info.plist',
        '--ios-build-config=$buildMode-$flavor',
        '--android-package-name=$bundleId',
        '--android-out=android/app/src/$flavor/google-services.json',
      ], workingDirectory: 'app');
    }
  }

  stdout.writeln('==========================================');
  stdout.writeln('[V] All configurations completed successfully!');
  stdout.writeln('==========================================');
}

bool _isCommandAvailable(String command) {
  try {
    final result = Process.runSync(Platform.isWindows ? 'where' : 'which', [
      command,
    ], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String _prompt(String message) {
  stdout.write(message);
  return stdin.readLineSync() ?? '';
}

Future<void> _runCommand(
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
    stderr.writeln(
      '[ERROR] Command "$command ${args.join(' ')}" failed with exit code $exitCode',
    );
    exit(exitCode);
  }
}
