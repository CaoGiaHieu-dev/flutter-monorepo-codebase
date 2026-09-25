import 'dart:io';

/// Directories a workspace discovery walk never descends into — the one
/// skip set shared by every tool that looks for packages (`pubspec.yaml`),
/// apps (`app_manifest.yaml`) or per-package output (`coverage/lcov.info`).
///
/// Build output, dependency caches and the platform runner folders of an
/// app (`android/`, `ios/`, …), which hold no workspace package but can
/// hold plugin symlinks and thousands of Gradle / Xcode files. Every hidden
/// directory (`.git`, `.dart_tool`, `.fvm`, `.idea`, …) is skipped too,
/// by [isSkippedDir].
///
/// Tools that must see *every* file — `arch_check`'s working-tree rules,
/// `docs_check`'s Markdown scan (a runner folder has READMEs), the theme
/// generator's platform-file copy — walk the tree themselves on purpose.
///
/// Uses `dart:io` only: `workspace_setup/configure.dart` imports it and
/// runs before `pub get`.
const Set<String> skippedDirs = {
  'build',
  'ephemeral',
  'node_modules',
  'Pods',
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
};

/// Whether a discovery walk skips a directory named [name].
bool isSkippedDir(String name) =>
    name.startsWith('.') || skippedDirs.contains(name);

/// Every file named [fileName] under [root], in a stable (sorted by path)
/// order. Symbolic links are not followed.
List<File> findWorkspaceFiles(String root, String fileName) {
  final out = <File>[];
  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        if (!isSkippedDir(name)) walk(entity);
      } else if (entity is File && name == fileName) {
        out.add(entity);
      }
    }
  }

  final start = Directory(root);
  if (start.existsSync()) walk(start);
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Every `pubspec.yaml` under [root] — one per workspace package, plus the
/// root's own when [root] is the repository.
List<File> findPubspecs(String root) =>
    findWorkspaceFiles(root, 'pubspec.yaml');

/// Every `app_manifest.yaml` under [root] — one per app.
List<File> findAppManifests(String root) =>
    findWorkspaceFiles(root, 'app_manifest.yaml');

String _basename(String path) {
  final parts = path.replaceAll('\\', '/').split('/')
    ..removeWhere((s) => s.isEmpty);
  return parts.isEmpty ? path : parts.last;
}
