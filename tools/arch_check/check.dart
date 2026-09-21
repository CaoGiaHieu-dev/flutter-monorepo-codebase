import 'dart:io';

import 'package:path/path.dart' as p;

import '../unused_checker/monorepo_helper.dart';
import '../unused_checker/output_formatter.dart';

/// Mechanical enforcement of the architecture rules in
/// `.agents/AGENTS.md` / `docs/en/reference/01_rules.md`.
///
/// A rule nobody can break by accident is a rule; a rule you have to remember
/// is a suggestion. Every check here maps to a numbered rule and prints
/// `file:line` so a violation is one click away.
///
/// Exit code 0 = clean, 1 = at least one blocking violation.

// ---------------------------------------------------------------------------
// Approved exceptions — the ONLY upward edges allowed out of `core/*`.
// Printed on every run so they stay visible instead of rotting in a comment.
// Adding one here without updating `.agents/AGENTS.md` is itself a violation.
// ---------------------------------------------------------------------------
const _approvedUpwardEdges = <String, String>{
  'provider_state_management -> domain_core':
      'Needs Result<T> and PaginatedEntity<T> for executeOperation / '
          'PaginatedViewWidget.',
  'platform_kernel -> domain_core':
      'ErrorHandler produces AppFailure, which lives in domain_core. '
          'Core -> Domain is the correct Clean Architecture direction.',
  'bloc_state_management -> domain_core':
      'BlocViewState.error carries AppFailure directly.',
};

/// The pure-Dart tier: packages that must run on a Dart VM, with no Flutter
/// binding anywhere in their dependency closure.
///
/// `platform_kernel` is the foundation every other package may depend on, so
/// its dependency list becomes everyone's — the reason it is held to a harder
/// line than `core_*`. A `*_contracts` package is the public surface between
/// two modules and stays here for the same reason: an interface that cannot
/// import `BuildContext` cannot quietly become a widget API.
///
/// `modules/*/domain` is covered by R2 instead, which predates this rule.
bool _isPureDartTier(String packageName) =>
    packageName == 'platform_kernel' || packageName.endsWith('_contracts');

/// Anything that drags a Flutter binding in.
const _flutterBound = <String>{
  'flutter',
  'flutter_localizations',
  'flutter_web_plugins',
  'material_ui',
  'cupertino_ui',
  'go_router',
  'provider',
  'flutter_bloc',
};

/// Packages every Dart package may import without declaring: they ship with
/// the SDK rather than through `pubspec.yaml` resolution.
const _sdkPackages = <String>{
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'flutter_driver',
  'integration_test',
};

/// Generated output. `.g.dart` / `.freezed.dart` are conventional; the
/// `firebase_options_*` files are emitted by the FlutterFire CLI and are
/// gitignored, so they carry no repo-authored constants.
bool _isGenerated(String posixPath) {
  final name = p.posix.basename(posixPath);
  return name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.config.dart') ||
      name.endsWith('.module.dart') ||
      name.endsWith('.mocks.dart') ||
      name.startsWith('firebase_options_') ||
      posixPath.contains('/gen/') ||
      posixPath.contains('/generated/');
}

class Violation {
  Violation(this.rule, this.location, this.message);

  /// Rule id, e.g. `R1`.
  final String rule;

  /// `path:line`, or just `path` when the whole file is the subject.
  final String location;
  final String message;
}

/// A `package:` directive found in a source file, with the line it sits on.
class _PackageRef {
  _PackageRef(this.package, this.line);

  final String package;
  final int line;
}

/// Matches `import`/`export` of a `package:` URI.
///
/// `dotAll` matters: a directive wraps across lines when it carries a
/// `show` / `hide` / `as` clause. Without it `.*?;` stops at the newline and
/// the directive is silently missed — the same bug that once made
/// `check_unused_packages.dart` under-report.
final _packageDirective = RegExp(
  r'''^\s*(?:import|export)\s+['"]package:([a-zA-Z0-9_]+)(?:/[^'"]*)?['"].*?;''',
  multiLine: true,
  dotAll: true,
);

/// Public `static const` declaration (i.e. not `_privateName`).
final _publicStaticConst = RegExp(
  r'''^\s*static\s+const\s+(?:[\w<>,\s\?]+\s+)?([A-Za-z]\w*)\s*=''',
  multiLine: true,
);

List<_PackageRef> _packageRefsIn(String content) {
  final refs = <_PackageRef>[];
  for (final m in _packageDirective.allMatches(content)) {
    final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
    refs.add(_PackageRef(m.group(1)!, line));
  }
  return refs;
}

List<String> _dartFilesUnderLib(String packageRoot) {
  final libDir = Directory(p.posix.join(packageRoot, 'lib'));
  if (!libDir.existsSync()) return const [];
  final out = <String>[];
  for (final e in libDir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || p.extension(e.path) != '.dart') continue;
    out.add(p.posix.normalize(e.path.replaceAll(r'\', '/')));
  }
  return out;
}

/// The architectural layer a package belongs to, derived from its **name**.
///
/// Deliberately not from its path. The previous version split the directory on
/// `packages` and returned the next segment, so a package moved anywhere else
/// resolved to the empty string — and R1, R2 and R3 all silently passed for it.
/// A guardrail that turns itself off when files move is worse than no
/// guardrail, because the report still says clean.
///
/// Naming is already enforced (§4), so the name is the more reliable signal,
/// and it survives any relayout.
String _layerOf(MonorepoPackage pkg) {
  final name = pkg.name;
  if (name.startsWith('domain_')) return 'domain';
  if (name.startsWith('data_')) return 'data';
  if (name.startsWith('feature_')) return 'features';
  if (name == 'app' || name.startsWith('app_')) return 'app';
  if (name == 'core_tools') return 'tools';
  // platform_kernel, core_*, *_state_management: the infrastructure ring.
  return 'core';
}

/// Matches a bare sizing extension — a number or a closing paren followed by
/// `.w`, `.h`, `.sp`, `.r`, `.spMin`, `.dg`, `.dm`.
///
/// `core_responsive` declares no such extension on `num`, so these do not
/// resolve against it. This catches one declared elsewhere, which would
/// type-check while reading a value that never notifies anyone.
///
/// Anchored on the receiver so ordinary members (`rect.width`, `state.hasData`)
/// never match, and the trailing boundary keeps `.hour` or `.round()` out.
final RegExp _bareSizingExtension = RegExp(
  r'[\d)]\.(spMin|sp|dg|dm|w|h|r)\b(?!\s*\()',
);

/// Drops a trailing `//` comment so commented-out or explanatory text does not
/// trip a rule. Naive about `//` inside string literals, which is acceptable
/// here: the cost is a false positive on a line that mentions a URL, and the
/// message points straight at it.
String _stripComment(String line) {
  final i = line.indexOf('//');
  return i == -1 ? line : line.substring(0, i);
}

/// A type declared at the top level of a file — `class`, `mixin` or the Dart 3
/// class modifiers. Used to enumerate what `core_di` publishes.
final _typeDeclaration = RegExp(
  r'^\s*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*'
  r'(?:class|mixin)\s+([A-Z]\w*)',
  multiLine: true,
);

/// A type named as a supertype or as an Injectable binding target:
/// `implements X`, `extends X`, `with X`, `@LazySingleton(as: X)`.
///
/// Comma lists are captured whole (`implements A, B`) and split by the caller,
/// which is what makes a dual-registering controller like `AuthProvider` —
/// `implements IAuthSessionState, IAuthRefreshListenable` — register both.
final _supertypeRef = RegExp(
  r'(?:implements|extends|with|as:)\s*([A-Z]\w*(?:\s*,\s*[A-Z]\w*)*)',
);

/// A DI lookup that throws when the type is unregistered.
///
/// `getItOrNull<` and `getAllOrEmpty<` do not match: the literal `getIt<` /
/// `getAll<` requires the `<` immediately after, and those two identifiers
/// carry more characters before theirs.
final _throwingLookup = RegExp(r'\bget(?:It|All)<([A-Z]\w*)>');

/// Every type `core_di` declares.
Set<String> _typesDeclaredIn(String packageRoot) {
  final out = <String>{};
  for (final file in _dartFilesUnderLib(packageRoot)) {
    if (_isGenerated(file)) continue;
    for (final m in _typeDeclaration.allMatches(File(file).readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// Maps each contract type to the feature packages that implement it.
///
/// A contract implemented only by a feature is a contract whose registration
/// disappears with that feature — which is exactly the set R8 governs. A
/// contract implemented in the app shell (`IThemeStorage`) is always present,
/// so it is deliberately not in this map and never trips the rule.
Map<String, Set<String>> _featureImplementers(
  Iterable<MonorepoPackage> packages,
  Set<String> contractTypes,
) {
  final out = <String, Set<String>>{};
  for (final pkg in packages) {
    if (_layerOf(pkg) != 'features') continue;
    for (final file in _dartFilesUnderLib(pkg.rootPath)) {
      if (_isGenerated(file)) continue;
      final content = File(file).readAsStringSync();
      for (final m in _supertypeRef.allMatches(content)) {
        for (final raw in m.group(1)!.split(',')) {
          final name = raw.trim();
          if (contractTypes.contains(name)) {
            (out[name] ??= <String>{}).add(pkg.name);
          }
        }
      }
    }
  }
  return out;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    _printHelp();
    exit(0);
  }

  OutputFormatter.printHeader(
    'Architecture Check',
    subtitle: 'Mechanical enforcement of .agents/AGENTS.md',
  );

  final stopwatch = Stopwatch()..start();
  final root = p.posix.normalize(Directory.current.path.replaceAll(r'\', '/'));
  final packages = MonorepoHelper.getPackages(root);

  if (packages.isEmpty) {
    OutputFormatter.printError(
      'No workspace packages found. Run this from the repository root.',
    );
    exit(1);
  }

  OutputFormatter.printInfo(
    'Approved upward exceptions out of core/* '
    '(${_approvedUpwardEdges.length}):',
  );
  for (final entry in _approvedUpwardEdges.entries) {
    stdout.writeln('    • ${entry.key}');
    stdout.writeln('        ${entry.value}');
  }
  stdout.writeln('');

  final blocking = <Violation>[];
  final warnings = <Violation>[];

  // R8 needs a repo-wide view before the per-package pass: which `core_di`
  // contracts are implemented *only* by a feature, and therefore vanish when
  // that feature is removed.
  // No `firstOrNull` here: it is a `package:collection` extension and this
  // tool deliberately depends only on `dart:io` and `package:path`.
  MonorepoPackage? coreDi;
  for (final pkg in packages.values) {
    if (pkg.name == 'core_di') {
      coreDi = pkg;
      break;
    }
  }
  final removableContracts = coreDi == null
      ? const <String, Set<String>>{}
      : _featureImplementers(
          packages.values,
          _typesDeclaredIn(coreDi.rootPath),
        );

  for (final pkg in packages.values) {
    final layer = _layerOf(pkg);
    final files = _dartFilesUnderLib(pkg.rootPath);
    // Parsed from YAML by MonorepoHelper — a hand-rolled line scanner
    // silently drops entries after a blank line inside the block.
    final declared = pkg.dependencies;

    // --- R1 / R3: forbidden edges, by import ------------------------------
    for (final file in files) {
      if (_isGenerated(file)) continue;
      final content = File(file).readAsStringSync();
      final rel = p.posix.relative(file, from: root);

      for (final ref in _packageRefsIn(content)) {
        final target = ref.package;
        final edge = '${pkg.name} -> $target';

        if (layer == 'core') {
          final upward =
              target.startsWith('feature_') ||
              target.startsWith('data_') ||
              target.startsWith('domain_');
          if (upward && !_approvedUpwardEdges.containsKey(edge)) {
            blocking.add(
              Violation(
                'R1',
                '$rel:${ref.line}',
                'core package `${pkg.name}` imports `$target`. '
                    'Core must not depend on an outer ring.',
              ),
            );
          }
        }

        if (layer == 'features') {
          if (target.startsWith('feature_') && target != pkg.name) {
            blocking.add(
              Violation(
                'R3',
                '$rel:${ref.line}',
                '`${pkg.name}` imports another feature `$target`. '
                    'Talk through a core_di contract instead.',
              ),
            );
          }
          if (target.startsWith('data_')) {
            blocking.add(
              Violation(
                'R3',
                '$rel:${ref.line}',
                '`${pkg.name}` imports data package `$target`. '
                    'Features depend on domain, never on data.',
              ),
            );
          }
        }

        if (layer == 'domain') {
          const banned = {'flutter', 'dio', 'retrofit', 'material_ui', 'cupertino_ui'};
          if (banned.contains(target)) {
            blocking.add(
              Violation(
                'R2',
                '$rel:${ref.line}',
                'domain package `${pkg.name}` imports `$target`. '
                    'Domain is pure Dart.',
              ),
            );
          }
        }

        // --- R5: used but not declared ------------------------------------
        final selfOrSdk = target == pkg.name || _sdkPackages.contains(target);
        if (!selfOrSdk && !declared.contains(target)) {
          blocking.add(
            Violation(
              'R5',
              '$rel:${ref.line}',
              '`${pkg.name}` imports `$target` but does not declare it in '
                  '`dependencies:`. Pub Workspaces hide this locally; it '
                  'breaks when the package is extracted.',
            ),
          );
        }
      }
    }

    // --- R1 / R2: forbidden edges, by pubspec -----------------------------
    final pubspecRel = p.posix.relative(
      p.posix.join(pkg.rootPath, 'pubspec.yaml'),
      from: root,
    );

    if (layer == 'core') {
      for (final dep in declared) {
        final upward =
            dep.startsWith('feature_') ||
            dep.startsWith('data_') ||
            dep.startsWith('domain_');
        if (upward && !_approvedUpwardEdges.containsKey('${pkg.name} -> $dep')) {
          blocking.add(
            Violation(
              'R1',
              pubspecRel,
              'core package `${pkg.name}` declares `$dep`. '
                  'Add it to the approved list in AGENTS.md, or remove it.',
            ),
          );
        }
      }
    }

    if (layer == 'domain' &&
        (declared.contains('flutter') ||
            declared.contains('material_ui') ||
            declared.contains('cupertino_ui'))) {
      blocking.add(
        Violation(
          'R2',
          pubspecRel,
          'domain package `${pkg.name}` declares Flutter/UI dependencies under '
              '`dependencies:`. Domain must resolve without the Flutter SDK.',
        ),
      );
    }

    // --- R4: shared constants belong in utils/ ----------------------------
    for (final file in files) {
      if (_isGenerated(file)) continue;
      // Design-token exception: core_base_ui keeps its tokens in styles/,
      // which names the intent better than a generic utils/ bucket.
      if (file.contains('/utils/') || file.contains('/styles/')) continue;

      final content = File(file).readAsStringSync();
      final rel = p.posix.relative(file, from: root);
      for (final m in _publicStaticConst.allMatches(content)) {
        final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
        blocking.add(
          Violation(
            'R4',
            '$rel:$line',
            'public constant `${m.group(1)}` declared outside `utils/`. '
                'Move it so the package owns its constants in one place '
                '(private `_name` constants may stay where they are used).',
          ),
        );
      }
    }

    // --- R7: responsive sizing goes through BuildContext -------------------
    // `16.w` and `context.w(16)` return the same number, but only the second
    // registers an InheritedWidget dependency, so only the second rebuilds
    // when the metrics change (rotation, split-screen, desktop resize). The
    // bare form is therefore a silent staleness bug, not a style preference.
    for (final file in files) {
      final source = File(file).readAsStringSync();
      if (!source.contains('core_responsive')) continue;

      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComment(lines[i]);
        // A numeric or closing-paren receiver followed by a sizing extension.
        for (final m in _bareSizingExtension.allMatches(code)) {
          blocking.add(
            Violation(
              'R7',
              '${p.posix.relative(file, from: root)}:${i + 1}',
              'bare `.${m.group(1)}` sizing extension — use '
                  '`context.${m.group(1)}(value)` so the widget rebuilds when '
                  'screen metrics change. If no BuildContext is reachable, '
                  'read the value from one before the first `await` and pass '
                  'it in.',
            ),
          );
        }
      }
    }

    // --- R9: the pure-Dart tier stays pure ---------------------------------
    // Checked in the pubspec as well as the imports. R2 checks imports only,
    // which is how `data_auth` kept a clean bill of health while declaring
    // firebase_auth and google_sign_in — Flutter plugins that cannot run on a
    // Dart VM — without a single `package:flutter` import in its source.
    if (_isPureDartTier(pkg.name)) {
      for (final dep in declared) {
        if (_flutterBound.contains(dep)) {
          blocking.add(
            Violation(
              'R9',
              p.posix.relative(
                p.posix.join(pkg.rootPath, 'pubspec.yaml'),
                from: root,
              ),
              '`${pkg.name}` is pure-Dart tier but declares `$dep`. '
                  'Move whatever needs it into a Flutter-side package.',
            ),
          );
        }
      }
      for (final file in files) {
        if (_isGenerated(file)) continue;
        final content = File(file).readAsStringSync();
        for (final ref in _packageRefsIn(content)) {
          if (_flutterBound.contains(ref.package)) {
            blocking.add(
              Violation(
                'R9',
                '${p.posix.relative(file, from: root)}:${ref.line}',
                '`${pkg.name}` is pure-Dart tier and must not import '
                    '`${ref.package}`.',
              ),
            );
          }
        }
      }
    }

    // --- R8: removable contracts resolve optionally ------------------------
    // `getAll<T>()` throws when `T` is unregistered and `getIt<T>()` throws
    // when nothing implements it. For a contract whose only implementer is a
    // feature package, that is a crash the moment the feature is removed —
    // and features are removable by design (AGENTS §22). The failure is
    // invisible to `flutter analyze` because the lookup type-checks fine; it
    // surfaces at runtime, on whichever screen happens to call it.
    for (final file in files) {
      if (_isGenerated(file)) continue;
      final lines = File(file).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = _stripComment(lines[i]);
        for (final m in _throwingLookup.allMatches(code)) {
          final type = m.group(1)!;
          final owners = removableContracts[type];
          if (owners == null) continue;
          // The owning feature may resolve its own contract eagerly: if the
          // package is in the build at all, so is its registration.
          if (owners.contains(pkg.name)) continue;

          blocking.add(
            Violation(
              'R8',
              '${p.posix.relative(file, from: root)}:${i + 1}',
              '`$type` is implemented only by ${owners.join(', ')}, which is '
                  'a removable feature — a throwing lookup here crashes any '
                  'build without it. Use `getItOrNull<$type>()` (or '
                  '`getAllOrEmpty`) and handle the null case.',
            ),
          );
        }
      }
    }

    // --- R6: generated files should not be hand-edited (warning) ----------
    for (final file in files) {
      final name = p.posix.basename(file);
      final isConventional =
          name.endsWith('.g.dart') ||
          name.endsWith('.freezed.dart') ||
          name.endsWith('.config.dart') ||
          name.endsWith('.module.dart');
      if (!isConventional) continue;

      final head = File(file).readAsStringSync();
      final marker = head.length > 400 ? head.substring(0, 400) : head;
      if (!marker.contains('GENERATED CODE') &&
          !marker.contains('dart format width') &&
          !marker.contains('coverage:ignore-file')) {
        warnings.add(
          Violation(
            'R6',
            p.posix.relative(file, from: root),
            'generated file is missing its generator header — it may have '
                'been hand-edited. Re-run `dart run build_runner build -d '
                '--workspace`.',
          ),
        );
      }
    }
  }

  stopwatch.stop();
  _report(packages.length, blocking, warnings, stopwatch.elapsed);
  exit(blocking.isEmpty ? 0 : 1);
}

void _report(
  int packageCount,
  List<Violation> blocking,
  List<Violation> warnings,
  Duration elapsed,
) {
  const ruleTitles = <String, String>{
    'R1': 'Dependency direction (core must not reach outward)',
    'R2': 'Domain is pure Dart',
    'R3': 'Feature boundaries',
    'R4': 'Package constants live in utils/',
    'R5': 'Every import is declared',
    'R6': 'Generated files are not hand-edited',
    'R7': 'Responsive sizing goes through BuildContext',
    'R8': 'Removable contracts resolve optionally',
    'R9': 'The pure-Dart tier stays pure',
  };

  if (warnings.isNotEmpty) {
    OutputFormatter.printWarning('${warnings.length} warning(s):');
    for (final w in warnings) {
      stdout.writeln('    ${w.location}');
      stdout.writeln('      ${w.message}');
    }
    stdout.writeln('');
  }

  if (blocking.isEmpty) {
    OutputFormatter.printSuccess(
      'All architecture rules hold across $packageCount packages.',
    );
    OutputFormatter.printTiming('Architecture check', elapsed);
    return;
  }

  final byRule = <String, List<Violation>>{};
  for (final v in blocking) {
    byRule.putIfAbsent(v.rule, () => []).add(v);
  }

  OutputFormatter.printError(
    '${blocking.length} violation(s) across ${byRule.length} rule(s):',
  );
  stdout.writeln('');

  final ids = byRule.keys.toList()..sort();
  for (final id in ids) {
    OutputFormatter.printSection(
      '$id — ${ruleTitles[id] ?? ''}',
      icon: '🚫',
    );
    for (final v in byRule[id]!) {
      stdout.writeln('    ${v.location}');
      stdout.writeln('      ${v.message}');
    }
    stdout.writeln('');
  }

  OutputFormatter.printInfo(
    'Rules and rationale: docs/en/reference/01_rules.md '
    '(authoritative: .agents/AGENTS.md)',
  );
  OutputFormatter.printTiming('Architecture check', elapsed);
}

void _printHelp() {
  stdout.writeln('''
Architecture Check — enforces the layering rules in .agents/AGENTS.md.

USAGE
  dart tools/arch_check/check.dart [--help]

Run from the repository root. Exits 0 when clean, 1 on any blocking violation,
so it can gate CI.

RULES CHECKED
  R1  Dependency direction
      No platform/* package may import or declare a feature_*, data_* or
      domain_* package, except for the approved edges listed at the top of the
      run. Checked in both lib/ imports and pubspec.yaml.

  R2  Domain is pure Dart
      No modules/*/domain/lib file may import flutter, dio or retrofit, and no
      domain pubspec may declare `flutter` under `dependencies:`
      (dev_dependencies is fine).

  R3  Feature boundaries
      A feature may not import another feature, nor any data_* package.
      Cross-feature work goes through a contract in core_di.

  R4  Package constants live in utils/
      A *public* `static const` must sit under lib/utils/ or lib/src/utils/.
      Private `_name` constants may stay beside the code that uses them, and
      core_base_ui/src/styles/ is an approved exception for design tokens.
      A package with no shared constants needs no utils/ directory — this rule
      never asks for an empty folder.

  R5  Every import is declared
      Every `package:X` used under lib/ must appear in that package's
      `dependencies:`. Pub Workspaces share one package_config.json, so an
      undeclared import still compiles locally and only breaks on extraction.

  R6  Generated files are not hand-edited  (warning only, never blocks)
  R9  The pure-Dart tier stays pure
      `platform_kernel` and every `*_contracts` package must neither import a
      Flutter-bound package nor declare one in `pubspec.yaml`. The pubspec half
      matters: a package can declare a Flutter plugin and never write
      `import 'package:flutter/...'`, which R2 would pass.

  R8  Removable contracts resolve optionally
      A `core_di` contract whose only implementer lives in modules/*/feature
      disappears when that feature is removed. `getIt<T>()` and `getAll<T>()`
      throw in that case, so such a type must be resolved with
      `getItOrNull<T>()` / `getAllOrEmpty<T>()` and a fallback. The owning
      feature may still resolve its own contract eagerly.
      Invisible to `flutter analyze`: the lookup type-checks, then crashes at
      runtime on whichever screen calls it.

  R7  Responsive sizing goes through BuildContext
      `16.w` and `context.w(16)` compute the same number, but only the
      second registers an InheritedWidget dependency, so only the second
      rebuilds when metrics change (rotation, split-screen, resize).
      Checked only in files that import core_responsive.
      Files named *.g.dart / *.freezed.dart / *.config.dart / *.module.dart
      should carry their generator header.

EXCLUDED FROM SCANNING
  Generated output: *.g.dart, *.freezed.dart, *.config.dart, *.module.dart,
  *.mocks.dart, firebase_options_*.dart, and anything under gen/ or generated/.
''');
}
