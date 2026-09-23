import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One app in the workspace: a directory holding an `app_manifest.yaml`.
class WorkspaceApp {
  WorkspaceApp(this.id, this.dir);

  /// `app.id` from the manifest — what `--app` matches against.
  final String id;

  /// The app's directory, relative to the repository root, `/`-separated.
  final String dir;
}

/// Every app under [root], sorted by id.
///
/// Uses the same marker and the same skip list as `composer`, so the tools
/// agree on what an app is. Relying on a directory *name* is what broke
/// `firebase_config.dart` and `theme_setting.dart` the day `app/` became
/// `apps/mobile/`.
List<WorkspaceApp> discoverApps([String root = '.']) {
  final out = <WorkspaceApp>[];
  const skip = {'.git', '.dart_tool', 'build', 'packages', 'modules'};

  void walk(Directory dir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (skip.contains(name)) continue;
        walk(e);
      } else if (e is File && name == 'app_manifest.yaml') {
        final doc = loadYaml(e.readAsStringSync()) as YamlMap;
        final id = (doc['app'] as YamlMap)['id'] as String;
        final dir = p.relative(e.parent.path, from: root);
        out.add(WorkspaceApp(id, p.split(dir).join('/')));
      }
    }
  }

  walk(Directory(root));
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// Picks the app a tool should act on, or exits with a message saying why it
/// cannot.
///
/// `--app <id>` selects one explicitly. Without it the workspace must hold
/// exactly one app: acting on an arbitrary one of several — generating
/// Firebase options or launcher icons for the wrong bundle ID — is worse
/// than refusing.
WorkspaceApp selectApp(List<String> args, {String root = '.'}) {
  final apps = discoverApps(root);
  if (apps.isEmpty) {
    stderr.writeln(
      '[ERROR] No app found: nothing in this workspace contains an '
      'app_manifest.yaml. Run this from the repository root.',
    );
    exit(1);
  }

  final flag = args.indexOf('--app');
  if (flag != -1) {
    if (flag + 1 >= args.length) {
      stderr.writeln('[ERROR] --app needs an id.');
      exit(64);
    }
    final id = args[flag + 1];
    for (final app in apps) {
      if (app.id == id) return app;
    }
    stderr.writeln('[ERROR] No app with id "$id". Known apps:');
    for (final app in apps) {
      stderr.writeln('  - ${app.id}  (${app.dir})');
    }
    exit(64);
  }

  if (apps.length == 1) return apps.single;

  stderr.writeln(
    '[ERROR] ${apps.length} apps found; say which one with --app <id>:',
  );
  for (final app in apps) {
    stderr.writeln('  - ${app.id}  (${app.dir})');
  }
  exit(64);
}
