import 'dart:io';

import 'package:path/path.dart' as p;

import '../arch_check/dart_source.dart';
import '../shared/toolchain.dart';

const _usage = '''
Usage: dart tools/barrel_generator/generate.dart <package>/lib

Writes the package's one barrel, lib/<package_name>.dart: an `export` of every
Dart file under lib/, sorted, then runs `dart format` on it.

  dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib

There is exactly one barrel per package. A directory barrel is deleted: a
file holding nothing but `export` lines of files in the same package, with or
without the auto-generated header (an older generator wrote them; so does a
hand). One that has the header and also holds code keeps the code and loses the
exports. A file that re-exports ANOTHER package (`export 'package:x/x.dart';`,
a regular source file, like core_common's kernel.dart) is not a directory
barrel: it stays and is exported like any file.
Every `export` directive in the package barrel is replaced, however it is
written (single or double quotes, `export'x'`, a `show` / `hide` clause across
lines); everything else in it (library doc comment, `library;`) is kept.

Not exported: `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `part of` files,
`firebase_options*.dart`, lib/gen/ and hidden directories. Generated files
that ARE libraries (`module.module.dart`, lib/src/gen/**) are exported when
present on disk — run it after gen-l10n / build_runner.

Exits 64 when the path is not a package's lib/ directory or on a flag, 1 when
generation or formatting fails.''';

/// The header every generated export block starts with.
const _header = '// Auto-generated exports, do not edit manually.';

String _basename(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? '' : parts.last;
}

/// `lib/` and `lib` name the same directory. Left in, the trailing separator
/// made the package directory's basename empty and the barrel came out as
/// `lib/.dart`.
String _stripTrailingSeparators(String path) {
  var out = path;
  while (out.length > 1 && (out.endsWith('/') || out.endsWith('\\'))) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }
  // A flag is never a path: `--help` used to be taken for a directory name.
  final flag = args.where((a) => a.startsWith('-')).firstOrNull;
  if (flag != null || args.length > 1) {
    stderr.writeln(
      flag != null
          ? '[ERROR] Unknown flag: $flag'
          : '[ERROR] Expected one path, got: ${args.join(' ')}',
    );
    stderr.writeln(_usage);
    exit(64);
  }

  if (args.isEmpty) {
    stderr.writeln('[ERROR] Expected a package lib/ directory.');
    stderr.writeln(_usage);
    exit(64);
  }
  final targetDir = _stripTrailingSeparators(args[0]);
  final lib = Directory(targetDir);
  if (!lib.existsSync()) {
    stderr.writeln('[ERROR] Directory "$targetDir" does not exist.');
    exit(64);
  }
  final pubspec = File(p.join(lib.parent.path, 'pubspec.yaml'));
  if (_basename(lib.path) != 'lib' || !pubspec.existsSync()) {
    stderr.writeln(
      '[ERROR] "$targetDir" is not a package lib/ directory (a lib/ next to '
      'a pubspec.yaml).',
    );
    exit(64);
  }
  final nameMatch = RegExp(
    r'^name:\s+([a-zA-Z0-9_]+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (nameMatch == null) {
    stderr.writeln('[ERROR] No package name in ${pubspec.path}.');
    exit(64);
  }
  final barrel = File(p.join(lib.path, '${nameMatch.group(1)}.dart'));

  stdout.writeln('\n[INFO] Writing ${barrel.path}...');

  try {
    final sources = <String>[];
    for (final file in _dartFiles(lib)) {
      if (p.equals(file.path, barrel.path)) continue;
      final content = file.readAsStringSync();
      if (_isLegacyBarrel(content)) {
        file.deleteSync();
        stdout.writeln('  - Deleted directory barrel: ${file.path}');
        continue;
      }
      if (content.contains(_header)) {
        file.writeAsStringSync(_withoutExports(content));
        stdout.writeln('  - Removed exports from: ${file.path}');
      }
      if (_isExported(file.path, content)) {
        sources.add(
          p.posix.joinAll(p.split(p.relative(file.path, from: lib.path))),
        );
      }
    }
    _deleteEmptyDirectories(lib);
    sources.sort();
    _writeBarrel(barrel, [for (final s in sources) "export '$s';"]);

    stdout.writeln('\n[INFO] Formatting "$targetDir"...');
    // Through the repo's toolchain (`fvm dart` when FVM is set up), not the
    // SDK that happens to run this script.
    final result = Process.runSync(dartExecutable, [
      ...dartArgs,
      'format',
      targetDir,
    ], runInShell: true);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      stderr.writeln(
        '[ERROR] dart format failed (exit ${result.exitCode}). The barrel '
        'was written but not formatted.',
      );
      exit(1);
    }

    stdout.writeln('\n[SUCCESS] Barrel generated: ${sources.length} exports.');
  } on FileSystemException catch (e) {
    stderr.writeln('[ERROR] ${e.path}: ${e.message}');
    exit(1);
  }
}

/// Every `.dart` file under [lib], skipping `lib/gen` (flutter_gen output,
/// exported by nothing) and hidden directories. `lib/src/gen` — gen-l10n and
/// flutter_gen output a package does export — is walked.
List<File> _dartFiles(Directory lib) {
  final out = <File>[];
  void walk(Directory dir, {required bool top}) {
    final entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      final name = _basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (top && name == 'gen') continue;
        walk(e, top: false);
      } else if (e is File && name.endsWith('.dart')) {
        out.add(e);
      }
    }
  }

  walk(lib, top: true);
  return out;
}

bool _isExported(String path, String content) {
  final name = _basename(path);
  if (name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.mocks.dart') ||
      name.endsWith('_test.dart') ||
      name.startsWith('firebase_options')) {
    return false;
  }
  return !RegExp(r'^part\s+of\s+', multiLine: true).hasMatch(content);
}

/// A directory barrel: a lib file with nothing in it but `export` directives
/// (`library;` and comments aside). With the generator's header it is one an
/// older, per-directory version of this tool wrote — even an empty one. Without
/// it, it is one somebody wrote by hand, and it counts only when every export
/// names a file of this package (a relative URI): `export 'package:x/x.dart';`
/// is a deliberate re-export that stays an ordinary source file.
bool _isLegacyBarrel(String content) {
  final scanned = DartSource.scan(content);
  if (scanned.directives.any((d) => d.keyword != 'export')) return false;
  final rest = DartSource.scan(_withoutExportDirectives(content)).code
      .replaceAll(RegExp(r'\blibrary\b[^;]*;'), '')
      .trim();
  if (rest.isNotEmpty) return false;
  if (content.contains(_header)) return true;
  final exports = scanned.directives.where((d) => d.keyword == 'export');
  return exports.isNotEmpty &&
      exports.every((d) => d.uris.every((u) => !u.contains(':')));
}

String _withoutExports(String content) {
  final kept = _withoutExportDirectives(content)
      .split('\n')
      .where((l) => l.trim() != _header)
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return '${kept.trimLeft().trimRight()}\n';
}

/// [content] without any `export` directive: found by the lexer, so single and
/// double quotes, `export'x'`, a `show` / `hide` clause that wraps over lines
/// and a conditional configuration all go, and an `export` inside a comment or
/// a string stays. The rest of the line goes with the directive.
String _withoutExportDirectives(String content) {
  final ranges = [
    for (final d in DartSource.scan(content).directives)
      if (d.keyword == 'export') (d.start, d.end),
  ];
  if (ranges.isEmpty) return content;
  final out = StringBuffer();
  var at = 0;
  for (final (start, end) in ranges) {
    out.write(content.substring(at, start));
    at = end;
    // Trailing blanks and one line break belong to the directive.
    while (at < content.length && (content[at] == ' ' || content[at] == '\t')) {
      at++;
    }
    if (at < content.length && content[at] == '\r') at++;
    if (at < content.length && content[at] == '\n') at++;
  }
  out.write(content.substring(at));
  return out.toString();
}

void _deleteEmptyDirectories(Directory dir) {
  for (final sub in dir.listSync().whereType<Directory>()) {
    _deleteEmptyDirectories(sub);
    if (sub.listSync().isEmpty) {
      sub.deleteSync();
      stdout.writeln('  - Deleted empty directory: ${sub.path}');
    }
  }
}

/// Keeps what a person wrote in the barrel (its doc comment, `library;`,
/// imports) and replaces every `export` directive with [exports].
void _writeBarrel(File barrel, List<String> exports) {
  final kept = <String>[];
  if (barrel.existsSync()) {
    for (final line in _withoutExportDirectives(
      barrel.readAsStringSync(),
    ).split(RegExp(r'\r?\n'))) {
      if (line.trim() == _header) continue;
      kept.add(line);
    }
  }
  while (kept.isNotEmpty && kept.last.trim().isEmpty) {
    kept.removeLast();
  }
  final block = [_header, ...exports];
  final out = kept.isEmpty ? block : [...kept, '', ...block];
  barrel.writeAsStringSync('${out.join('\n')}\n');
}
