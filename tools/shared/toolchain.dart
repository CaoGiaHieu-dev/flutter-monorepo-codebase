import 'dart:io';

/// How every tool that shells out to `dart` / `flutter` decides whether to
/// go through FVM.
///
/// Two conditions must BOTH hold, because either one alone gives a wrong
/// answer: a repo can pin a version in `.fvmrc` on a machine that never
/// installed FVM, and a machine can have FVM installed for other projects
/// while this repo pins nothing. Checks `.fvmrc` (used by this repo) and the
/// legacy `.fvm/fvm_config.json`, relative to the working directory — every
/// tool runs from the repository root.
bool get useFvm => _useFvm ??= _detectFvm();

bool? _useFvm;

bool _detectFvm() {
  final hasConfig =
      File('.fvmrc').existsSync() || File('.fvm/fvm_config.json').existsSync();
  if (!hasConfig) return false;
  try {
    return Process.runSync('fvm', ['--version'], runInShell: true).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

/// `dart` or `fvm`, paired with [dartArgs].
String get dartExecutable => useFvm ? 'fvm' : 'dart';

/// `flutter` or `fvm`, paired with [flutterArgs].
String get flutterExecutable => useFvm ? 'fvm' : 'flutter';

/// Arguments to put before the real ones: `['dart']` under FVM, else none.
List<String> get dartArgs => useFvm ? const ['dart'] : const [];

/// Arguments to put before the real ones: `['flutter']` under FVM, else none.
List<String> get flutterArgs => useFvm ? const ['flutter'] : const [];

/// One line saying which toolchain the run will use.
void reportToolchain() {
  stdout.writeln(
    useFvm
        ? '[INFO] FVM configured and installed. Using "fvm dart/flutter".'
        : '[INFO] Not using FVM. Using the global dart/flutter.',
  );
}
