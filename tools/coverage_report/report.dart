import 'dart:io';

import 'package:path/path.dart' as p;

import '../shared/workspace.dart';

/// Per-package line coverage from the `coverage/lcov.info` files that
/// `flutter test --coverage` leaves in each package.
///
/// CI Gate 3 runs every package's tests with `--coverage`, then this prints a
/// Markdown table — one row per package plus a total — to stdout and, on
/// GitHub Actions, to the job summary (`$GITHUB_STEP_SUMMARY`). Advisory by
/// default: no threshold, exit 0. An adopter who wants a floor passes `--min`
/// (the total) and/or `--min-package` (every package).
///
/// Generated files are left out of every number — `*.g.dart`,
/// `*.freezed.dart`, `*.config.dart`, `*.module.dart`, `*.gr.dart`,
/// `*.mocks.dart` and anything under a `gen/` directory (gen-l10n output,
/// asset classes). Nobody writes tests for them, and counting them made
/// coverage a measure of how much code build_runner emitted.

const String _usage = '''
Usage: dart tools/coverage_report/report.dart [options] [<lcov.info> ...]

Prints per-package line coverage as a Markdown table, and appends it to
\$GITHUB_STEP_SUMMARY when that is set (GitHub Actions). With no files given,
every */coverage/lcov.info under the repository root is read (what
`flutter test --coverage` writes in each package). The package is named from
the pubspec.yaml beside coverage/. Generated files (*.g.dart, *.freezed.dart,
*.config.dart, *.module.dart, *.gr.dart, *.mocks.dart, gen/) are excluded.

Options:
  --min <pct>           Exit 1 when TOTAL line coverage is below <pct> (0-100).
  --min-package <pct>   Exit 1 when ANY package is below <pct>.
  --no-summary          Do not write to \$GITHUB_STEP_SUMMARY.
  -h, --help            Print this help.

Without --min / --min-package the report is advisory and exits 0 — unless no
lcov.info was found at all (exit 1: the tests did not run with --coverage).
Exit 64 on a bad argument.''';

/// Whether [path] (as lcov's `SF:` names it) is generated code.
bool isGeneratedFile(String path) {
  final posix = path.replaceAll('\\', '/');
  const suffixes = [
    '.g.dart',
    '.freezed.dart',
    '.config.dart',
    '.module.dart',
    '.gr.dart',
    '.mocks.dart',
  ];
  if (suffixes.any(posix.endsWith)) return true;
  return posix.split('/').contains('gen');
}

/// Line counts for one source file.
class FileCoverage {
  FileCoverage(this.path, this.found, this.hit);

  final String path;
  final int found;
  final int hit;
}

/// Parses an lcov tracefile into one [FileCoverage] per `SF:` record, from
/// its `DA:` lines (a line listed twice counts once, hit if either is).
/// Generated files are dropped.
List<FileCoverage> parseLcov(String lcov) {
  final out = <FileCoverage>[];
  String? file;
  final lines = <int, bool>{};
  for (final raw in lcov.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      file = line.substring(3);
      lines.clear();
    } else if (line.startsWith('DA:') && file != null) {
      final parts = line.substring(3).split(',');
      if (parts.length < 2) continue;
      final number = int.tryParse(parts[0]);
      final hits = int.tryParse(parts[1]);
      if (number == null || hits == null) continue;
      lines[number] = (lines[number] ?? false) || hits > 0;
    } else if (line == 'end_of_record' && file != null) {
      if (!isGeneratedFile(file)) {
        out.add(
          FileCoverage(file, lines.length, lines.values.where((h) => h).length),
        );
      }
      file = null;
    }
  }
  return out;
}

/// One package's row.
class PackageCoverage {
  PackageCoverage(this.name, this.dir, this.files);

  final String name;

  /// Repo-relative, `/`-separated.
  final String dir;
  final List<FileCoverage> files;

  int get found => files.fold(0, (sum, f) => sum + f.found);
  int get hit => files.fold(0, (sum, f) => sum + f.hit);

  /// Percentage, or null when the package has no instrumented line.
  double? get percent => found == 0 ? null : hit * 100 / found;
}

String _pct(double? value) => value == null ? '—' : value.toStringAsFixed(1);

/// The Markdown report for [packages], sorted by directory.
String renderTable(List<PackageCoverage> packages) {
  final sorted = [...packages]..sort((a, b) => a.dir.compareTo(b.dir));
  final found = sorted.fold(0, (sum, p) => sum + p.found);
  final hit = sorted.fold(0, (sum, p) => sum + p.hit);
  final buffer = StringBuffer()
    ..writeln('### Line coverage (advisory)')
    ..writeln()
    ..writeln('| Package | Path | Files | Lines | Covered | % |')
    ..writeln('|:--|:--|--:|--:|--:|--:|');
  for (final pkg in sorted) {
    buffer.writeln(
      '| `${pkg.name}` | `${pkg.dir}` | ${pkg.files.length} | ${pkg.found} '
      '| ${pkg.hit} | ${_pct(pkg.percent)} |',
    );
  }
  buffer
    ..writeln(
      '| **Total** | ${sorted.length} package(s) | '
      '${sorted.fold(0, (sum, p) => sum + p.files.length)} | $found | $hit '
      '| **${_pct(found == 0 ? null : hit * 100 / found)}** |',
    )
    ..writeln()
    ..writeln(
      'Generated files (`*.g.dart`, `*.freezed.dart`, `*.config.dart`, '
      '`*.module.dart`, `*.gr.dart`, `*.mocks.dart`, `gen/`) are excluded. '
      'Only files a test loaded appear in `lcov.info`, so an untested file '
      'that nothing imports does not lower the number.',
    );
  return buffer.toString();
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  double? min;
  double? minPackage;
  var summary = true;
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--min' || arg == '--min-package') {
      final value = i + 1 < args.length ? double.tryParse(args[i + 1]) : null;
      if (value == null || value < 0 || value > 100) {
        _usageError('$arg needs a percentage between 0 and 100.');
      }
      if (arg == '--min') {
        min = value;
      } else {
        minPackage = value;
      }
      i++;
    } else if (arg == '--no-summary') {
      summary = false;
    } else if (arg.startsWith('-')) {
      _usageError('Unknown option: $arg');
    } else {
      files.add(arg);
    }
  }

  final root = Directory.current.path;
  final traces = files.isEmpty
      ? _findLcovFiles(root)
      : [
          for (final f in files)
            if (File(f).existsSync())
              File(f).absolute.path
            else
              _usageError('No such file: $f'),
        ];
  if (traces.isEmpty) {
    stderr.writeln(
      '[ERROR] No coverage/lcov.info found under $root. Run the tests with '
      '`flutter test --coverage` first.',
    );
    exit(1);
  }

  final packages = [for (final trace in traces) _package(root, trace)];
  final table = renderTable(packages);
  stdout.writeln(table);

  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary && summaryPath != null && summaryPath.isNotEmpty) {
    File(summaryPath).writeAsStringSync('$table\n', mode: FileMode.append);
  }

  final failures = <String>[];
  final found = packages.fold(0, (sum, p) => sum + p.found);
  final hit = packages.fold(0, (sum, p) => sum + p.hit);
  final total = found == 0 ? 0.0 : hit * 100 / found;
  if (min != null && total < min) {
    failures.add(
      'Total line coverage ${total.toStringAsFixed(1)}% is below --min '
      '${min.toStringAsFixed(1)}%.',
    );
  }
  if (minPackage != null) {
    for (final pkg in packages) {
      final percent = pkg.percent;
      if (percent != null && percent < minPackage) {
        failures.add(
          '${pkg.name} (${pkg.dir}): ${percent.toStringAsFixed(1)}% is below '
          '--min-package ${minPackage.toStringAsFixed(1)}%.',
        );
      }
    }
  }
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('[FAIL] $failure');
    }
    exit(1);
  }
}

Never _usageError(String message) {
  stderr.writeln('[ERROR] $message');
  stderr.writeln('');
  stderr.writeln(_usage);
  exit(64);
}

/// The package that wrote [trace] (`<pkg>/coverage/lcov.info`).
PackageCoverage _package(String root, String trace) {
  final pkgDir = p.dirname(p.dirname(trace));
  var dir = p.relative(pkgDir, from: root).replaceAll('\\', '/');
  if (dir == '.') dir = '(root)';
  final pubspec = File(p.join(pkgDir, 'pubspec.yaml'));
  final name = pubspec.existsSync()
      ? RegExp(
              r'^name:\s*([\w]+)',
              multiLine: true,
            ).firstMatch(pubspec.readAsStringSync())?.group(1) ??
            p.basename(pkgDir)
      : p.basename(pkgDir);
  return PackageCoverage(
    name,
    dir,
    parseLcov(File(trace).readAsStringSync()),
  );
}

/// Every `coverage/lcov.info` under [root] — the shared workspace walk
/// (`tools/shared/workspace.dart`), sorted by path.
List<String> _findLcovFiles(String root) => [
  for (final file in findWorkspaceFiles(root, 'lcov.info'))
    if (p.basename(file.parent.path) == 'coverage') file.path,
];
