import 'dart:io';

import '../shared/app_locator.dart';
import '../shared/toolchain.dart';

/// Generates one app's per-flavor Firebase configuration.
///
/// ```bash
/// dart tools/firebase/firebase_config.dart              # the only app
/// dart tools/firebase/firebase_config.dart --app mobile # one of several
/// ```
///
/// Everything it writes belongs to that app — Firebase options identify one
/// bundle ID — so it all lands inside the app's directory:
///
/// - `lib/firebase/firebase_options_<flavor>.dart`, imported by the app's
///   own `lib/firebase/firebase_module.dart`
/// - `ios/flavors/<flavor>/GoogleService-Info.plist`
/// - `android/app/src/<flavor>/google-services.json`
const _usage = '''
Usage: dart tools/firebase/firebase_config.dart [--app <id>]

Generates one app's per-flavor Firebase configuration with the FlutterFire CLI:
  <app>/lib/firebase/firebase_options_<flavor>.dart
  <app>/ios/flavors/<flavor>/GoogleService-Info.plist
  <app>/android/app/src/<flavor>/google-services.json

Options:
  --app <id>   The app to configure (its app_manifest.yaml `app.id`). Required
               when the workspace holds more than one app.
  -h, --help   Show this help.

Interactive: it prompts for the Firebase project ID, the base bundle ID and the
flavors. Requires the Firebase CLI, logged in (`firebase login`), and installs
the FlutterFire CLI through `dart pub global activate` when it is missing.''';

/// How many times an unauthenticated run offers `firebase login` before it
/// gives up. `firebase login` exits 0 without logging in when it cannot open
/// a prompt, so an unbounded retry loop never ended.
const _maxLoginAttempts = 2;

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--app') {
      i++; // its value; selectApp validates it
      continue;
    }
    stderr.writeln('[ERROR] Unknown argument: ${args[i]}');
    stderr.writeln(_usage);
    exit(64);
  }

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

  final app = selectApp(args);
  stdout.writeln('[INFO] Configuring app "${app.id}" in ${app.dir}/');
  if (!File('${app.dir}/lib/firebase/firebase_module.dart').existsSync()) {
    stdout.writeln(
      '[!] ${app.dir}/lib/firebase/firebase_module.dart does not exist, so '
      'nothing will import the generated options. Copy the one from '
      'apps/mobile/lib/firebase/ if this app should use Firebase.',
    );
  }

  // The project ID, bundle ID and flavors are prompted for — there is no
  // flag form — so a run without a terminal could only fail later.
  if (!stdin.hasTerminal) {
    stderr.writeln(
      '[X] This script is interactive and stdin is not a terminal. Run it '
      'from a terminal, after `firebase login`.',
    );
    exit(1);
  }

  reportToolchain();
  final dartCmd = dartExecutable;

  // 1. The Firebase CLI is a global npm package. Installing it is the
  // user's call, not this script's.
  if (!_isCommandAvailable('firebase')) {
    stderr.writeln('[X] Firebase CLI (`firebase`) not found in PATH.');
    stderr.writeln('    Install it, then log in and re-run this script:');
    stderr.writeln('      npm install -g firebase-tools');
    stderr.writeln(
      '      (or see https://firebase.google.com/docs/cli#install_the_firebase_cli)',
    );
    stderr.writeln('      firebase login');
    exit(1);
  }

  // Check login status
  stdout.writeln('Checking Firebase login status...');
  var attempts = 0;
  while (!await _isLoggedIn()) {
    if (attempts == _maxLoginAttempts) {
      stderr.writeln(
        '[X] Still not logged in to Firebase after $attempts '
        '`firebase login` attempt(s). Run `firebase login` yourself, check '
        '`firebase projects:list` works, then re-run this script.',
      );
      exit(1);
    }
    attempts++;
    stdout.writeln(
      '[!] Firebase is not logged in or session expired. Running '
      '\'firebase login\' (attempt $attempts of $_maxLoginAttempts)...',
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

    // The two platforms suffix staging differently: Gradle's
    // `applicationIdSuffix` is `.stg`, the Xcode bundle id `.staging`. Each
    // Firebase client must match the id its platform actually builds, or
    // Gradle fails with "No matching client found".
    final isProd = flavor == 'prod' || flavor == 'production';
    final iosBundleId = isProd ? baseBundleId : '$baseBundleId.$flavor';
    final androidPackage = isProd
        ? baseBundleId
        : '$baseBundleId.${_androidSuffix[flavor] ?? flavor}';

    for (final buildMode in ['Debug', 'Profile', 'Release']) {
      stdout.writeln('=> Setting up $buildMode-$flavor');
      await _runCommand('flutterfire', [
        'config',
        '--yes',
        '--project=$projectId',
        '--out=lib/firebase/firebase_options_$flavor.dart',
        '--ios-bundle-id=$iosBundleId',
        '--ios-out=ios/flavors/$flavor/GoogleService-Info.plist',
        '--ios-build-config=$buildMode-$flavor',
        '--android-package-name=$androidPackage',
        '--android-out=android/app/src/$flavor/google-services.json',
      ], workingDirectory: app.dir);
    }
  }

  stdout.writeln('==========================================');
  stdout.writeln('[V] All configurations completed successfully!');
  stdout.writeln('==========================================');
}

/// `firebase projects:list` succeeds only with a valid session.
Future<bool> _isLoggedIn() async {
  final result = await Process.run('firebase', [
    'projects:list',
  ], runInShell: true);
  return result.exitCode == 0;
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

/// Android `applicationIdSuffix` per flavor where it differs from the flavor
/// name — see `productFlavors` in `apps/<id>/android/app/build.gradle.kts`.
const _androidSuffix = {'staging': 'stg'};
