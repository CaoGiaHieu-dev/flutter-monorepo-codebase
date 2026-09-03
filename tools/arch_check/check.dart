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
  'core_di -> domain_auth':
      'Agnostic stream contracts expose concrete entity types (UserEntity); '
          'generics would erase type-safety.',
  'provider_state_management -> domain_core':
      'Needs Result<T> and PaginatedEntity<T> for executeOperation / '
          'PaginatedViewWidget.',
  'core_common -> domain_core':
      'ErrorHandler produces AppFailure, which lives in domain_core. '
          'Core -> Domain is the correct Clean Architecture direction.',
  'bloc_state_management -> domain_core':
      'BlocViewState.error carries AppFailure directly.',
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

String _layerOf(String packageRoot) {
  final parts = p.posix.split(packageRoot);
  final i = parts.indexOf('packages');
  return (i >= 0 && i + 1 < parts.length) ? parts[i + 1] : '';
}

/// Matches a bare sizing extension left over from the old package — a number or a
/// closing paren followed by `.w`, `.h`, `.sp`, `.r`, `.spMin`, `.dg`, `.dm`.
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

  for (final pkg in packages.values) {
    final layer = _layerOf(pkg.rootPath);
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
          const banned = {'flutter', 'dio', 'retrofit'};
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

    if (layer == 'domain' && declared.contains('flutter')) {
      blocking.add(
        Violation(
          'R2',
          pubspecRel,
          'domain package `${pkg.name}` declares `flutter` under '
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
      No packages/core/* package may import or declare a feature_*, data_* or
      domain_* package, except for the approved edges listed at the top of the
      run. Checked in both lib/ imports and pubspec.yaml.

  R2  Domain is pure Dart
      No packages/domain/*/lib file may import flutter, dio or retrofit, and no
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
