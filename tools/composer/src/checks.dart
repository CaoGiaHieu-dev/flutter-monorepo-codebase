import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog.dart';
import 'manifest_v2.dart';

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
/// | V9  | a pinning decision per flavor where a declared platform can pin |
/// | V14 | no reason is empty, `TODO` or `TBD` |
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
