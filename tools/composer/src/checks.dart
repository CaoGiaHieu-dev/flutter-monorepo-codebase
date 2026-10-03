import 'dart:io';

import 'package:path/path.dart' as p;

import '../../arch_check/dart_source.dart';
import 'catalog.dart';
import 'facts_emit.dart';
import 'manifest_v2.dart';
import 'package_facts.dart';

/// The checks `composer verify` (CI Gate 0) holds an app's declaration to,
/// beyond the shape [parseDeclaration] enforces. Each returns one
/// `<file>: <key>: <problem>` line per defect, with the line to paste where
/// there is one.
///
/// | Check | Holds |
/// |:-:|:--|
/// | V2  | every optional catalog id has a declared state; no unknown id |
/// | V4  | the members of a bundle share one state |
/// | V5  | `splash: dart` needs capability `splash` provided |
/// | V6  | `committed` => the runner folder exists; `scaffold` => it does not |
/// | V8  | `push: true` needs `core_notifications` composed and supporting the platform; `window` only on a desktop platform |
/// | V9  | a pinning decision per flavor where a declared platform can pin |
/// | V14 | no reason is empty, `TODO` or `TBD` |
///
/// Two more run where the app's view is built (`sync` / `verify`), because they
/// need the composed packages: [checkPlatformSwitches] (V8) and
/// [checkPackagePlatforms] (V7). [checkComposition] holds V3, V10, V11 and V12
/// to the source — the static scan of `tools/shared/contract_scan.dart` and the
/// files an app owns.
///
/// V1 (closed vocabularies, types, ranges, `app.kind`) lives in the parser and
/// V13 (the generated regions equal regeneration) in `composer.dart`'s drift
/// pass.
List<String> checkDeclaration({
  required String rel,
  required AppDeclaration decl,
  required ShellCatalog catalog,
  required String appDir,
  required String appRel,
}) {
  final problems = <String>[];
  void bad(String key, String problem) => problems.add('$rel: $key: $problem');

  _capabilities(decl, catalog, bad);
  _splash(decl, bad);
  _runners(decl, appDir, appRel, bad);
  _pinning(decl, bad);
  return problems;
}

/// V2, V4, V14 for `capabilities:`.
void _capabilities(
  AppDeclaration decl,
  ShellCatalog catalog,
  void Function(String key, String problem) bad,
) {
  final known = catalog.declarableKeys;
  for (final key in decl.capabilities.keys) {
    if (!known.contains(key)) {
      bad(
        'capabilities.$key',
        'unknown contract id — `composer describe --catalog` lists them '
            '(${catalog.optionalKeys.join(', ')})',
      );
    }
  }

  // Which declaration covers each optional row, and whether two do.
  final covered = <String, String>{}; // row id -> the key that declares it
  for (final row in catalog.optional) {
    final keys = <String>[
      if (decl.capabilities.containsKey(row.id)) row.id,
      if (row.bundle != null && decl.capabilities.containsKey(row.bundle))
        row.bundle!,
    ];
    if (keys.length > 1) {
      bad(
        'capabilities.${keys.first}',
        '`${row.id}` is declared twice (${keys.join(' and ')}) — each '
            'contract is declared once',
      );
    }
    if (keys.isNotEmpty) covered[row.id] = keys.first;
  }

  final missing = <String>[];
  for (final key in catalog.optionalKeys) {
    final members = catalog.membersOf(key);
    final undeclared = [
      for (final m in members)
        if (!covered.containsKey(m.id)) m,
    ];
    if (undeclared.isEmpty) continue;
    // A bundle none of whose members is declared is asked for once, by its
    // bundle id; a half-declared bundle names the members that are missing.
    if (undeclared.length == members.length) {
      missing.add(key);
    } else {
      missing.addAll([for (final m in undeclared) m.id]);
    }
  }
  if (missing.isNotEmpty) {
    final lines = StringBuffer();
    for (final key in missing) {
      final row = catalog.membersOf(key).first;
      lines.write(
        '\n    $key: { state: absent, reason: "${_yaml(row.whenAbsent)}" }'
        '   # or `$key: provided` when a composed package registers it',
      );
    }
    bad(
      'capabilities',
      'no state declared for ${missing.join(', ')} — absence is a decision, '
          'so each optional contract is `provided` or `absent` with a reason. '
          'Add:$lines',
    );
  }

  // V4: the members of a bundle, declared one by one, share one state.
  for (final bundle in {
    for (final r in catalog.optional)
      if (r.bundle != null) r.bundle!,
  }) {
    final members = catalog.membersOf(bundle);
    final states = <String, bool>{
      for (final m in members)
        if (decl.capabilities[m.id] case final c?) m.id: c.provided,
    };
    if (states.values.toSet().length > 1) {
      final provided = [
        for (final e in states.entries)
          if (e.value) e.key,
      ];
      final absent = [
        for (final e in states.entries)
          if (!e.value) e.key,
      ];
      bad(
        'capabilities.${states.keys.first}',
        'the members of bundle `$bundle` share one state, but '
            '${provided.join(', ')} ${provided.length == 1 ? 'is' : 'are'} '
            'provided and ${absent.join(', ')} '
            '${absent.length == 1 ? 'is' : 'are'} absent — declare the bundle '
            'once: `$bundle: provided`',
      );
    }
  }

  // V14: a reason says why.
  for (final entry in decl.capabilities.entries) {
    final reason = entry.value.reason;
    if (reason != null && isEmptyReason(reason)) {
      final known = catalog.membersOf(entry.key);
      final suggestion = known.isEmpty
          ? ''
          : ', e.g. "${_yaml(known.first.whenAbsent)}"';
      bad(
        'capabilities.${entry.key}.reason',
        'a reason is empty, `TODO` or `TBD` — say why the app has none'
            '$suggestion',
      );
    }
  }
}

/// V5.
void _splash(
  AppDeclaration decl,
  void Function(String key, String problem) bad,
) {
  final splash = decl.capabilities['splash'];
  final provided = splash?.provided ?? false;
  for (final platform in decl.platforms) {
    if (platform.splash == 'dart' && !provided) {
      bad(
        'platforms.${platform.name}.splash',
        'a Dart splash needs capability `splash` provided, which '
            '`capabilities` ${splash == null ? 'does not declare' : 'declares absent'}'
            ' — compose a module that registers IAppSplashScreen and declare '
            '`splash: provided`, or use `splash: native`',
      );
    }
  }
}

/// V6.
void _runners(
  AppDeclaration decl,
  String appDir,
  String appRel,
  void Function(String key, String problem) bad,
) {
  for (final platform in decl.platforms) {
    final folder = p.posix.join(appRel, platform.name);
    final exists = Directory(p.posix.join(appDir, platform.name)).existsSync();
    if (platform.runner == 'committed' && !exists) {
      bad(
        'platforms.${platform.name}.runner',
        'declared `committed`, but $folder/ does not exist — run `flutter '
            'create --platforms=${platform.name} .` in $appRel, or declare '
            '`runner: scaffold`',
      );
    } else if (platform.runner == 'scaffold' && exists) {
      bad(
        'platforms.${platform.name}.runner',
        'declared `scaffold`, but $folder/ exists — the runner is committed, '
            'so declare `runner: committed`',
      );
    }
  }
}

/// V9 and the V14 half that concerns pin reasons.
void _pinning(
  AppDeclaration decl,
  void Function(String key, String problem) bad,
) {
  final pinnable = [
    for (final p in decl.platforms)
      if (kPinnablePlatforms.contains(p.name)) p.name,
  ];

  for (final entry in decl.flavors.entries) {
    final flavor = entry.key;
    final decision = entry.value;
    final key = 'flavors.$flavor.ssl_pinning';

    if (pinnable.isEmpty) {
      if (decision != null) {
        bad(
          key,
          'no declared platform can pin TLS (${decl.platforms.map((p) => p.name).join(', ')}: '
          'the browser owns TLS on web, the pinning plugin has no desktop '
          'implementation), so the key does nothing — delete it',
        );
      }
      continue;
    }

    if (decision == null) {
      if (flavor == 'dev') continue; // defaults to a stated, disabled decision
      bad(
        key,
        'decide — pins: ["<leaf>", "<backup>"] or disabled: "<reason>" '
        '(${pinnable.join(', ')} can pin)',
      );
      continue;
    }
    final reason = decision.disabledReason;
    if (reason != null && isEmptyReason(reason)) {
      bad(
        '$key.disabled',
        'a reason is empty, `TODO` or `TBD` — say why $flavor does not pin',
      );
    }
  }
}

String _yaml(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// V8: what a platform switches on must be something the app composes and the
/// platform has.
///
/// - `push: true` needs `core_notifications` composed, and its `platforms:`
///   to list the platform — otherwise the service would be asked to start
///   where Firebase Messaging has no implementation;
/// - `window` is for the desktop platforms, the only ones with a resizable
///   window.
///
/// Needs the composed packages, so it runs where the app's view is built
/// (`sync` / `verify`), not at manifest discovery.
List<String> checkPlatformSwitches(AppView view) {
  final problems = <String>[];
  void bad(String key, String problem) =>
      problems.add('${view.manifestPath}: $key: $problem');

  final notifications = view.packageFacts[kNotificationsPackage];
  for (final platform in view.declaration.platforms) {
    final name = platform.name;
    if (platform.push == true) {
      if (!view.composesNotifications) {
        bad(
          'platforms.$name.push',
          'push is on, but $kNotificationsPackage is not composed — add it to '
              'a di_groups entry, or delete the key (push is off without it)',
        );
      } else if (notifications != null && !notifications.supports(name)) {
        bad(
          'platforms.$name.push',
          'push is on, but $kNotificationsPackage does not support $name '
              '(its pubspec `platforms:` lists '
              '${notifications.platforms?.join(', ')}) — set `push: false`, '
              'or delete the key',
        );
      }
    }
    if (platform.window != null && !kDesktopPlatforms.contains(name)) {
      bad(
        'platforms.$name.window',
        'only a desktop platform (${kDesktopPlatforms.join(', ')}) has a '
            'resizable window — delete the key',
      );
    }
  }
  return problems;
}

/// V7: every platform the app declares is one every composed package works on.
///
/// A package says where it works in its own pubspec (`platforms:`, a key pub
/// accepts and validates nothing about — this is the check). `core_database`
/// lists no `web` because `drift/native` needs `dart:ffi`; an app that composes
/// it and declares `web` would compile for a platform that cannot link it.
/// Names the package and what pulled it in, so the fix is one edit.
List<String> checkPackagePlatforms(AppView view) {
  final problems = <String>[];
  for (final platform in view.declaration.platforms) {
    for (final name in view.composed.toList()..sort()) {
      final facts = view.packageFacts[name];
      if (facts == null || facts.supports(platform.name)) continue;
      problems.add(
        '${view.manifestPath}: platforms.${platform.name}: '
        '$name does not support ${platform.name} (its pubspec `platforms:` '
        'lists ${facts.platforms!.join(', ')}) but the app composes it '
        '${_origin(view, facts)} — declare only platforms every composed '
        'package supports, or stop composing it',
      );
    }
  }
  return problems;
}

/// How a composed package got into the app: its module, else its DI group.
String _origin(AppView view, PackageFacts facts) {
  final segments = facts.pubspec.split('/');
  final at = segments.indexOf('modules');
  if (at != -1 && at + 2 < segments.length) {
    return 'through module `${segments[at + 1]}` (${segments[at + 2]})';
  }
  final groups = [
    for (final g in view.groups)
      if (g.packages.contains(facts.name)) g.name,
  ];
  if (groups.isNotEmpty) {
    return 'in di_groups `${groups.join('`, `')}`';
  }
  return 'as an extra dependency';
}

/// V3, V10, V11 and V12: the declaration held to the source.
///
/// | Check | Holds |
/// |:-:|:--|
/// | V3  | `capabilities:` equals the code, both directions; every required row has an implementer |
/// | V10 | what a composed package needs the app to register (`composition.app_provides`) is registered, per flavor |
/// | V11 | the env files that exist hold exactly the keys `env:` declares |
/// | V12 | the entry point passes the profile; the DI smoke test exists and calls `checkAppContract` |
///
/// [root] is the repository root the app's files are read from.
List<String> checkComposition(AppView view, {required String root}) {
  final problems = <String>[];
  void bad(String file, String key, String problem) =>
      problems.add('$file: $key: $problem');
  final manifest = view.manifestPath;

  _contractsMatchCode(view, (key, problem) => bad(manifest, key, problem));
  _appProvides(view, (key, problem) => bad(manifest, key, problem));
  _envFiles(view, root, bad);
  _entryAndSmokeTest(view, root, bad);
  return problems;
}

/// V3.
void _contractsMatchCode(
  AppView view,
  void Function(String key, String problem) bad,
) {
  final catalog = view.catalog;

  for (final row in catalog.requiredRows) {
    if (view.providersOf(row.type).isNotEmpty) continue;
    final elsewhere = _elsewhere(view, row.type);
    bad(
      'di_groups',
      'required contract ${row.type} (`${row.id}`) has no implementer among '
          'the composed packages$elsewhere — without it the shell does this: '
          '${row.whenAbsent}',
    );
  }

  // The declaring key of each optional row: its own id, else its bundle.
  final byKey = <String, List<CatalogEntry>>{};
  for (final row in catalog.optional) {
    final key = view.declaration.capabilities.containsKey(row.id)
        ? row.id
        : row.bundle ?? row.id;
    (byKey[key] ??= []).add(row);
  }
  for (final entry in byKey.entries) {
    final key = entry.key;
    final state = view.capability(entry.value.first.id);
    if (state == null) continue; // V2 reports an undeclared contract
    final registered = {
      for (final row in entry.value) row: view.providersOf(row.type),
    };

    if (state.provided) {
      final missing = [
        for (final e in registered.entries)
          if (e.value.isEmpty) e.key,
      ];
      if (missing.isEmpty) continue;
      final hints = [for (final row in missing) _elsewhere(view, row.type)];
      bad(
        'capabilities.$key',
        'declared provided but no composed package or ${view.dir}/lib '
            'registers ${missing.map((r) => r.type).join(', ')}'
            '${hints.join()} — add the module that does, or declare it: '
            '$key: { state: absent, reason: '
            '"${_yaml(missing.first.whenAbsent)}" }',
      );
    } else {
      for (final e in registered.entries) {
        if (e.value.isEmpty) continue;
        final where = [
          for (final provision in e.value)
            '${provision.file}:${provision.line}',
        ];
        bad(
          'capabilities.$key',
          'declared absent but ${e.key.type} is registered at '
              '${where.join(', ')} — declare it provided ($key: provided), '
              'or stop composing what registers it',
        );
      }
    }
  }
}

/// " (feature_splash registers it but is not composed)" — the packages outside
/// the app's graph that do register [type]; empty when none does.
String _elsewhere(AppView view, String type) {
  final graph = view.graphPackages;
  final packages = {
    for (final provision in view.provisions.anywhere(type))
      if (!graph.contains(provision.package)) provision.package,
  }.toList()..sort();
  if (packages.isEmpty) return '';
  return ' (${packages.join(', ')} ${packages.length == 1 ? 'registers' : 'register'} '
      'it but ${packages.length == 1 ? 'is' : 'are'} not composed)';
}

/// V10.
void _appProvides(
  AppView view,
  void Function(String key, String problem) bad,
) {
  final appPackage = {view.pubspecName};
  for (final name in view.composed.toList()..sort()) {
    for (final need
        in view.packageFacts[name]?.appProvides ?? const <AppProvides>[]) {
      final registrations = view.provisions.of(need.type, appPackage);
      final hint = need.hint.replaceAll('<id>', view.id);
      final where = hint.isEmpty ? '' : ' — $hint';
      if (need.perFlavor) {
        for (final flavor in view.declaration.flavors.keys) {
          final covered = registrations.any(
            (r) => r.registration.coversEnvironment(flavor),
          );
          if (covered) continue;
          bad(
            'composition.app_provides',
            '$name needs the app to register ${need.type} for flavor '
                '`$flavor`, but nothing under ${view.dir}/lib does — add an '
                "@Environment('$flavor') ${need.type} to a @module there$where",
          );
        }
      } else if (registrations.isEmpty) {
        bad(
          'composition.app_provides',
          '$name needs the app to register ${need.type}, but nothing under '
              '${view.dir}/lib does$where',
        );
      }
    }
  }
}

/// A line of an env file: `KEY=value`, `#` comments and blank lines aside.
final RegExp _envLine = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=');

/// V11.
void _envFiles(
  AppView view,
  String root,
  void Function(String file, String key, String problem) bad,
) {
  final declared = {for (final e in view.declaration.env) e.key};
  for (final flavor in view.declaration.flavors.keys) {
    final name = kEnvFiles[flavor];
    if (name == null) continue;
    final rel = p.posix.join(view.dir, name);
    final file = File(p.join(root, rel));
    if (!file.existsSync()) continue; // not in the repo: nothing to compare
    final present = <String>{};
    for (final line in file.readAsLinesSync()) {
      final key = _envLine.firstMatch(line)?.group(1);
      if (key != null) present.add(key);
    }
    for (final key in present.toList()..sort()) {
      if (declared.contains(key)) continue;
      bad(
        rel,
        key,
        'not declared under `env:` in ${view.manifestPath} — declare it '
        '(`$key: { native_only: true }` when only Gradle or Xcode read '
        'it), or delete the line',
      );
    }
    for (final key in declared.toList()..sort()) {
      if (present.contains(key)) continue;
      bad(
        rel,
        key,
        'declared under `env:` in ${view.manifestPath} but missing from this '
        'file — add `$key=` (the value may be empty), or delete the key '
        'from the manifest',
      );
    }
  }
}

/// V12.
void _entryAndSmokeTest(
  AppView view,
  String root,
  void Function(String file, String key, String problem) bad,
) {
  final entry = p.posix.join(view.dir, view.declaration.entrypoint);
  final entryFile = File(p.join(root, entry));
  if (!entryFile.existsSync()) {
    bad(
      view.manifestPath,
      'app.entrypoint',
      '$entry does not exist — create it, or point `app.entrypoint` at the '
          'file that boots the app',
    );
  } else {
    final code = DartSource.scan(entryFile.readAsStringSync()).code;
    final call = RegExp(r'\brunShellApp\s*\(').firstMatch(code);
    if (call == null) {
      bad(
        view.manifestPath,
        'app.entrypoint',
        '$entry never calls runShellApp(...), the one boot every app goes '
            'through — `void main() => runShellApp(profile: appProfile, '
            'hooks: appHooks, configureDependencies: configureDependencies);`',
      );
    } else {
      final args = _arguments(code, call.end - 1);
      if (!RegExp(r'(^|[,(\s])profile\s*:').hasMatch(args)) {
        bad(
          view.manifestPath,
          'app.entrypoint',
          '$entry calls runShellApp without `profile:` — without it the app '
              'boots with no declaration: no platform or flavor check, no pin '
              'decision, no composition check. Pass `profile: appProfile`',
        );
      }
    }
  }

  final smoke = p.posix.join(view.dir, 'test', 'di_smoke_test.dart');
  final smokeFile = File(p.join(root, smoke));
  if (!smokeFile.existsSync()) {
    bad(
      smoke,
      'file',
      'missing — every app has a DI smoke test that boots each flavor and '
          'calls checkAppContract(...); copy it from another app and run '
          '`cd ${view.dir} && flutter test test/di_smoke_test.dart`',
    );
  } else if (!RegExp(
    r'\bcheckAppContract\s*\(',
  ).hasMatch(DartSource.scan(smokeFile.readAsStringSync()).code)) {
    bad(
      smoke,
      'checkAppContract',
      'never called — the smoke test must hold the declared capabilities to '
          'the graph the app builds: `expect(checkAppContract(appProfile, '
          'flavor: flavor, platform: platform).problems, isEmpty)`',
    );
  }
}

/// The text between the parenthesis at [open] and its match, nested argument
/// lists blanked, so a `profile:` inside a nested call is not mistaken for an
/// argument of the outer one.
String _arguments(String code, int open) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      if (depth == 1) continue;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) break;
    }
    out.write(depth <= 1 ? c : ' ');
  }
  return out.toString();
}
