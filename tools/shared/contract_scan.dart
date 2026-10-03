import 'dart:io';

import 'package:path/path.dart' as p;

import '../arch_check/dart_source.dart';

/// Static reading of dependency-injection contracts, shared by `arch_check`
/// (R8, R16) and `composer` (V3, V10 and the report's "implemented by"), so
/// the two tools cannot disagree about what a package provides.
///
/// Two scanners, kept apart because they answer different questions:
///
/// - **Implementers** ([ownersImplementing]) — which owners (a module) have a
///   class that `implements` / `extends` / `with` / `as:` a contract. This is
///   what R8 asks: "does this contract vanish when the module is removed?".
///   Deliberately generous (any supertype mention counts), and unchanged by the
///   move out of `arch_check/check.dart`.
/// - **Registrations** ([scanRegistrations]) — which types a source file
///   *registers* with GetIt. This is what composer asks: "does the graph
///   contain this type?". Narrower on purpose, because GetIt resolves the
///   exact type (RULE-14): `implements X` registers nothing.
///
/// Neither is a parser. A hand-written `getIt.register…` is invisible to the
/// second; `checkAppContract` re-derives the truth from the real graph and the
/// smoke test fails when the two disagree.

/// File names a generator conventionally writes. A name alone proves nothing:
/// anyone can call a hand-written file `size_ext.g.dart`, so [isGeneratedSource]
/// also asks for the generator's own header.
bool _hasGeneratedName(String name) =>
    name.endsWith('.g.dart') ||
    name.endsWith('.freezed.dart') ||
    name.endsWith('.config.dart') ||
    name.endsWith('.module.dart') ||
    name.endsWith('.gr.dart') ||
    name.endsWith('.mocks.dart') ||
    name == 'generated_plugin_registrant.dart';

/// Whether [name] is a file the FlutterFire CLI writes (gitignored, and in CI
/// a compile-only stub that carries no generator header).
bool _isFirebaseOptions(String name) => name.startsWith('firebase_options_');

/// The comment a generator writes before the first line of code: `GENERATED
/// CODE - DO NOT MODIFY BY HAND` (build_runner, flutter_gen), `Mocks generated
/// by Mockito`, `Generated file. Do not edit.` (plugin registrant), or the
/// `dart format` / coverage markers those generators add.
final RegExp _generatorHeader = RegExp(
  r'generated\s+(?:code|by|file)|do not edit|dart format width|'
  r'coverage:ignore-file',
  caseSensitive: false,
);

/// Whether [content]'s leading comment block (blank lines and `//` lines up to
/// the first line of code) carries a generator header.
bool hasGeneratorHeader(String content) {
  final head = StringBuffer();
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (t.isNotEmpty && !t.startsWith('//')) break;
    head.writeln(t);
  }
  return _generatorHeader.hasMatch(head.toString());
}

/// The first ~2 KB of [file] as text, or empty when it cannot be read.
String _headOf(String file) {
  try {
    final raf = File(file).openSync();
    try {
      final bytes = raf.readSync(2048);
      return String.fromCharCodes(bytes);
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return '';
  }
}

/// `output-dir:` of a package's `l10n.yaml`, as a path relative to the package
/// (`lib/src/gen/language`), memoised per package. `flutter gen-l10n` writes
/// no header in its Dart files, so the folder its configuration names is how
/// they are recognised.
final Map<String, String?> _l10nOutputDirs = {};

String? _l10nOutputDir(String packageRoot) =>
    _l10nOutputDirs.putIfAbsent(packageRoot, () {
      final file = File(p.posix.join(packageRoot, 'l10n.yaml'));
      if (!file.existsSync()) return null;
      final m = RegExp(
        r'^\s*output-dir\s*:\s*([^\s#]+)',
        multiLine: true,
      ).firstMatch(file.readAsStringSync());
      return m == null
          ? null
          : p.posix.normalize(m.group(1)!.replaceAll(RegExp('[\'"]'), ''));
    });

/// Whether [posixPath], a file of the package at [packageRoot], is generated
/// output that carries no repo-authored declarations or imports.
///
/// Read against the path **below the package**, never the absolute one: a
/// checkout cloned into `~/gen/app` or `/srv/generated/ci` has `gen` in every
/// path, and the old test on the whole path skipped every file there.
///
/// A file counts only when its name or folder says so *and* the generator
/// vouches for it:
///
/// - a conventional name (`*.g.dart`, `*.freezed.dart`, `*.config.dart`,
///   `*.module.dart`, `*.gr.dart`, `*.mocks.dart`, the plugin registrant) or a
///   file under a `gen/` / `generated/` folder, and
/// - the generator's header in its leading comment, or — for `flutter gen-l10n`,
///   which writes none — a place in the package's `l10n.yaml` `output-dir`.
///
/// A hand-written `size_ext.g.dart`, or a hand-written file dropped into
/// `lib/src/gen/`, therefore stays under every rule (R6 reports the first).
/// `firebase_options_*.dart` is the one exception: the FlutterFire CLI
/// (gitignored) and the CI stub both lack a header.
bool isGeneratedSource(String posixPath, {required String packageRoot}) {
  final file = posixPath.replaceAll(r'\', '/');
  final rel = p.posix.isWithin(packageRoot, file)
      ? p.posix.relative(file, from: packageRoot)
      : file;
  final name = p.posix.basename(rel);
  if (_isFirebaseOptions(name)) return true;
  final segments = p.posix.split(p.posix.dirname(rel));
  final inGenFolder =
      segments.contains('gen') || segments.contains('generated');
  if (!_hasGeneratedName(name) && !inGenFolder) return false;
  if (hasGeneratorHeader(_headOf(file))) return true;
  final l10n = _l10nOutputDir(packageRoot);
  return l10n != null && p.posix.dirname(rel) == l10n;
}

/// Whether [name] looks like generator output at all — the half of
/// [isGeneratedSource] that does not read the file.
bool hasGeneratedName(String name) => _hasGeneratedName(name);

/// The directory of the package that owns [file]: the nearest ancestor below
/// [repoRoot] holding a `pubspec.yaml`, or [repoRoot] itself when none does.
String packageRootOf(String file, String repoRoot) {
  var dir = p.posix.dirname(file.replaceAll(r'\', '/'));
  while (dir.length > repoRoot.length && p.posix.isWithin(repoRoot, dir)) {
    if (File(p.posix.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    dir = p.posix.dirname(dir);
  }
  return repoRoot;
}

/// Every `.dart` file under `<packageRoot>/lib`, POSIX paths, unsorted.
List<String> dartFilesUnderLib(String packageRoot) {
  final libDir = Directory(p.posix.join(packageRoot, 'lib'));
  if (!libDir.existsSync()) return const [];
  final out = <String>[];
  for (final e in libDir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || p.extension(e.path) != '.dart') continue;
    out.add(p.posix.normalize(e.path.replaceAll(r'\', '/')));
  }
  return out;
}

/// The hand-written Dart under `<packageRoot>/lib`: [dartFilesUnderLib] without
/// the generated output, sorted.
List<String> handWrittenDartUnderLib(String packageRoot) => [
  for (final f in dartFilesUnderLib(packageRoot))
    if (!isGeneratedSource(f, packageRoot: packageRoot)) f,
]..sort();

// ---------------------------------------------------------------------------
// Declared types and implementers (R8, R16)
// ---------------------------------------------------------------------------

/// A type declared at the top level of a file — `class`, `mixin` or the Dart 3
/// class modifiers. Used to enumerate what `core_di` publishes.
final RegExp typeDeclaration = RegExp(
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
///
/// A supertype may carry an import prefix (`implements c.IFoo`) and type
/// arguments (`implements IFoo<Bar>, IBaz`); the caller strips the prefix.
final RegExp supertypeRef = RegExp(
  r'(?:implements|extends|with|as:)\s*'
  r'((?:\w+\s*\.\s*)?[A-Z]\w*(?:\s*<[^;{}()]*?>)?'
  r'(?:\s*,\s*(?:\w+\s*\.\s*)?[A-Z]\w*(?:\s*<[^;{}()]*?>)?)*)',
);

/// The type names in one [supertypeRef] capture: the comma-separated names,
/// each without its import prefix and type arguments.
List<String> supertypeNames(String capture) {
  final out = <String>[];
  var depth = 0;
  final current = StringBuffer();
  void flush() {
    final name = current.toString().trim();
    current.clear();
    if (name.isEmpty) return;
    out.add(name.split('.').last.trim());
  }

  for (final c in capture.split('')) {
    if (c == '<') {
      depth++;
    } else if (c == '>') {
      depth--;
    } else if (depth == 0 && c == ',') {
      flush();
    } else if (depth == 0) {
      current.write(c);
    }
  }
  flush();
  return out;
}

/// Every type declared in the hand-written Dart under `<packageRoot>/lib`.
Set<String> typesDeclaredIn(String packageRoot) {
  final out = <String>{};
  for (final file in dartFilesUnderLib(packageRoot)) {
    if (isGeneratedSource(file, packageRoot: packageRoot)) continue;
    // Comments and strings blanked: a commented-out `class IOld` or a
    // template in a string declares nothing.
    final code = DartSource.scan(File(file).readAsStringSync()).code;
    for (final m in typeDeclaration.allMatches(code)) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// One package whose declarations belong to an [owner] — `auth` for
/// `modules/auth/data` — or to nobody (`owner == null`, skipped).
class ScanUnit {
  const ScanUnit(this.owner, this.rootPath);

  final String? owner;
  final String rootPath;
}

/// Maps each contract type in [contractTypes] to the owners whose packages name
/// it as a supertype or binding target.
///
/// A contract implemented only inside `modules/` is a contract whose
/// registration disappears with that module. That includes a data-layer
/// implementer: `IAuthSessionGateway` lives in `data_auth`, and a throwing
/// lookup of it crashes a build without auth just as surely as one of a
/// feature's contract. A contract implemented in the app shell
/// (`IThemeStorage`) has no owner here, so it is not in the map.
Map<String, Set<String>> ownersImplementing(
  Iterable<ScanUnit> units,
  Set<String> contractTypes,
) {
  final out = <String, Set<String>>{};
  for (final unit in units) {
    final owner = unit.owner;
    if (owner == null) continue;
    for (final file in dartFilesUnderLib(unit.rootPath)) {
      if (isGeneratedSource(file, packageRoot: unit.rootPath)) continue;
      // Comment- and string-stripped: prose such as "works with ISessionState"
      // or a commented-out `class Old implements IFoo` is not an implementer.
      final code = DartSource.scan(File(file).readAsStringSync()).code;
      for (final m in supertypeRef.allMatches(code)) {
        for (final name in supertypeNames(m.group(1)!)) {
          if (contractTypes.contains(name)) {
            (out[name] ??= <String>{}).add(owner);
          }
        }
      }
    }
  }
  return out;
}

/// An optional DI lookup — `getItOrNull<X>` or `getAllOrEmpty<X>` — in code
/// whose comments and strings are already blanked.
final RegExp optionalLookup = RegExp(
  r'\bget(?:ItOrNull|AllOrEmpty)<([A-Z]\w*)>',
);

/// One optional lookup found in a file.
class Lookup {
  const Lookup(this.type, this.line);

  final String type;
  final int line;
}

/// The optional lookups in [source], comments and string literals excluded.
List<Lookup> optionalLookupsIn(String source) {
  final scanned = DartSource.scan(source);
  return [
    for (final m in optionalLookup.allMatches(scanned.code))
      Lookup(m.group(1)!, scanned.lineOf(m.start)),
  ];
}

// ---------------------------------------------------------------------------
// Registrations (V3, V10, the report)
// ---------------------------------------------------------------------------

/// How a type came to be registered.
enum RegistrationKind {
  /// A class carrying `@Injectable` / `@Singleton` / `@LazySingleton` and no
  /// `as:` — the class's own type.
  annotatedClass,

  /// An annotation's `as: X` — the class is bound as `X`.
  boundAs,

  /// A member of a class annotated `@module`, declared with type `X`.
  moduleMember,
}

/// One type a source file registers with GetIt.
class Registration {
  const Registration({
    required this.type,
    required this.file,
    required this.line,
    required this.kind,
    required this.environments,
  });

  /// The registered type (`ISessionState`), generics dropped.
  final String type;

  /// The file, as handed to [scanRegistrations].
  final String file;

  /// 1-based line of the annotation or member that registers it.
  final int line;

  final RegistrationKind kind;

  /// The injectable environments it is limited to (`dev`, `prod`, ...); empty
  /// when it applies to every environment.
  final Set<String> environments;

  /// Whether the registration is live in [environment].
  bool coversEnvironment(String environment) =>
      environments.isEmpty || environments.contains(environment);

  @override
  String toString() => '$type@$file:$line (${kind.name})';
}

/// The annotations that register a class.
const Set<String> _registeringAnnotations = {
  'Injectable',
  'injectable',
  'Singleton',
  'singleton',
  'LazySingleton',
  'lazySingleton',
};

/// `@dev` / `@prod` / `@test` — injectable's environment constants.
const Set<String> _environmentConstants = {'dev', 'prod', 'test', 'staging'};

/// Reads [files] and returns every registration they hold.
///
/// Rule (GetIt resolves the exact type, RULE-14):
///
/// 1. a class carrying a registering annotation is registered as itself — or,
///    when the annotation has `as: X`, as `X` and only `X`;
/// 2. a member of a class annotated `@module` is registered as its declared
///    type (`Future<X>` as `X`), whether or not the member is itself
///    annotated, private members excepted.
///
/// Comments and string literals are blanked first, so a doc comment that shows
/// `@LazySingleton(as: IFoo)` as an example registers nothing.
List<Registration> scanRegistrations(Iterable<String> files) {
  final out = <Registration>[];
  for (final file in files) {
    final String source;
    try {
      source = File(file).readAsStringSync();
    } on FileSystemException {
      continue; // not UTF-8, or vanished: not ours to judge
    }
    out.addAll(registrationsIn(source, file: file));
  }
  return out;
}

/// [scanRegistrations] over one [source] text. [file] only labels the result.
List<Registration> registrationsIn(String source, {String file = ''}) {
  final scanned = DartSource.scan(source);
  final code = scanned.code;
  final out = <Registration>[];

  for (final head in _classHead.allMatches(code)) {
    final cls = head.group(1)!;
    final annotations = _annotationsBefore(code, source, head.start);
    if (annotations.isEmpty) continue;
    final environments = {
      for (final a in annotations) ..._envFromAnnotation(a),
    };

    // 1. A registering annotation: the class, or what `as:` binds it to.
    for (final a in annotations) {
      if (!_registeringAnnotations.contains(a.name)) continue;
      final line = scanned.lineOf(a.start);
      final bound = a.boundTypes;
      for (final type in bound.isEmpty ? [cls] : bound) {
        out.add(
          Registration(
            type: type,
            file: file,
            line: line,
            kind: bound.isEmpty
                ? RegistrationKind.annotatedClass
                : RegistrationKind.boundAs,
            environments: environments,
          ),
        );
      }
    }

    // 2. The members of an `@module` class.
    if (annotations.any((a) => a.name == 'module')) {
      final open = code.indexOf('{', head.end);
      if (open == -1) continue;
      final close = _matching(code, open, '{', '}');
      if (close == -1) continue;
      for (final member in _topLevelMembers(code, source, open + 1, close)) {
        final type = member.type;
        if (type == null || member.name.startsWith('_')) continue;
        out.add(
          Registration(
            type: type,
            file: file,
            line: scanned.lineOf(member.start),
            kind: RegistrationKind.moduleMember,
            environments: member.environments,
          ),
        );
      }
    }
  }
  return out;
}

/// An annotation read from the blanked code, its arguments from the raw text.
class _Annotation {
  _Annotation(this.name, this.start, this.end, this.rawArguments, this.code);

  final String name;
  final int start;
  final int end;

  /// The text between the parentheses, strings intact; empty without any.
  final String rawArguments;

  /// The same span in blanked code.
  final String code;

  /// `as: X` — the types the annotation binds, generics dropped.
  List<String> get boundTypes => [
    for (final m in RegExp(r'\bas\s*:\s*([A-Z]\w*)').allMatches(code))
      m.group(1)!,
  ];
}

/// The annotation whose `@` is at [at] in [code]; [source] has the same
/// offsets (the scanner replaces characters one for one).
_Annotation _annotationAt(String code, String source, int at) {
  final nameMatch = RegExp(r'@([\w.]+)').matchAsPrefix(code, at)!;
  var end = nameMatch.end;
  var rawArgs = '';
  var codeArgs = '';
  var probe = end;
  while (probe < code.length && _isSpace(code.codeUnitAt(probe))) {
    probe++;
  }
  if (probe < code.length && code[probe] == '(') {
    final close = _matching(code, probe, '(', ')');
    if (close != -1) {
      rawArgs = source.substring(probe + 1, close);
      codeArgs = code.substring(probe + 1, close);
      end = close + 1;
    }
  }
  return _Annotation(nameMatch.group(1)!, at, end, rawArgs, codeArgs);
}

final RegExp _classHead = RegExp(
  r'(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
  r'class\s+([A-Z]\w*)',
);

/// The annotations written directly in front of the declaration that starts at
/// [declarationStart], in source order.
List<_Annotation> _annotationsBefore(
  String code,
  String source,
  int declarationStart,
) {
  final out = <_Annotation>[];
  var at = declarationStart;
  while (true) {
    var j = at - 1;
    while (j >= 0 && _isSpace(code.codeUnitAt(j))) {
      j--;
    }
    if (j < 0) break;
    if (code[j] == ')') {
      var depth = 0;
      var open = -1;
      for (var k = j; k >= 0; k--) {
        if (code[k] == ')') depth++;
        if (code[k] == '(') {
          depth--;
          if (depth == 0) {
            open = k;
            break;
          }
        }
      }
      if (open == -1) break;
      j = open - 1;
      while (j >= 0 && _isSpace(code.codeUnitAt(j))) {
        j--;
      }
    }
    var k = j + 1;
    while (k > 0 && (_isWord(code.codeUnitAt(k - 1)) || code[k - 1] == '.')) {
      k--;
    }
    if (k == 0 || k == j + 1 || code[k - 1] != '@') break;
    final annotation = _annotationAt(code, source, k - 1);
    out.insert(0, annotation);
    at = k - 1;
  }
  return out;
}

/// The injectable environments an [annotation] names.
Set<String> _envFromAnnotation(_Annotation a) {
  final name = a.name.split('.').last;
  if (name == 'Environment') return _envFromEnvironmentArgs(a.rawArguments);
  if (_environmentConstants.contains(name) && a.rawArguments.isEmpty) {
    return {name};
  }
  if (_registeringAnnotations.contains(name)) {
    return _envFromArguments(a.rawArguments);
  }
  return const {};
}

/// `@Environment('dev')` and `@Environment(Environment.dev)`.
Set<String> _envFromEnvironmentArgs(String args) {
  final literal = RegExp('''['"](\\w+)['"]''').firstMatch(args);
  if (literal != null) return {literal.group(1)!};
  final constant = RegExp(r'Environment\.(\w+)').firstMatch(args);
  return constant == null ? const {} : {constant.group(1)!};
}

/// `env: ['dev', Environment.prod]` inside a registering annotation.
Set<String> _envFromArguments(String args) {
  final m = RegExp(r'\benv\s*:\s*\[([^\]]*)\]').firstMatch(args);
  if (m == null) return const {};
  final out = <String>{};
  for (final s in RegExp('''['"](\\w+)['"]''').allMatches(m.group(1)!)) {
    out.add(s.group(1)!);
  }
  for (final c in RegExp(r'Environment\.(\w+)').allMatches(m.group(1)!)) {
    out.add(c.group(1)!);
  }
  return out;
}

/// A member declared directly in a class body.
class _Member {
  _Member(this.start, this.name, this.type, this.environments);

  final int start;
  final String name;

  /// The declared type, `Future<X>` unwrapped, generics dropped; null for
  /// anything that is not `Type name`.
  final String? type;
  final Set<String> environments;
}

final RegExp _memberHead = RegExp(
  r'^(?:static\s+)?(?:external\s+)?'
  r'(?:(?:Future|FutureOr)\s*<\s*)?([A-Z]\w*)\s*(?:<[^()]*?>)?\s*>?\s+'
  r'(?:get\s+)?([A-Za-z_]\w*)',
);

/// The members of the class body between [from] and [to] (exclusive): what a
/// statement at brace depth one looks like once nested blocks and argument
/// lists are blanked.
List<_Member> _topLevelMembers(String code, String source, int from, int to) {
  // Same length as the span of [code]: everything nested in (...), {...} or
  // [...] becomes a blank, so offsets stay valid. A member ends at a `;` or at
  // the `}` that closes its body, both at depth zero.
  final flat = StringBuffer();
  final ends = <int>[]; // offsets into the span
  var depth = 0;
  for (var i = from; i < to; i++) {
    final c = code[i];
    final isOpen = c == '(' || c == '{' || c == '[';
    final isClose = c == ')' || c == '}' || c == ']';
    if (isOpen) {
      flat.write(depth == 0 ? c : ' ');
      depth++;
    } else if (isClose) {
      depth--;
      flat.write(depth == 0 ? c : ' ');
      if (depth == 0 && c == '}') ends.add(i - from);
    } else if (depth == 0) {
      flat.write(c);
      if (c == ';') ends.add(i - from);
    } else {
      flat.write(c == '\n' ? '\n' : ' ');
    }
  }
  final text = flat.toString();
  if (ends.isEmpty || ends.last != text.length - 1) ends.add(text.length);

  final out = <_Member>[];
  var begin = 0;
  for (final end in ends) {
    final statementStart = from + begin;
    final statementEnd = from + end;
    begin = end + 1;
    var cursor = statementStart;
    while (cursor < statementEnd && _isSpace(code.codeUnitAt(cursor))) {
      cursor++;
    }
    final annotations = <_Annotation>[];
    while (cursor < statementEnd && code[cursor] == '@') {
      final a = _annotationAt(code, source, cursor);
      annotations.add(a);
      cursor = a.end;
      while (cursor < statementEnd && _isSpace(code.codeUnitAt(cursor))) {
        cursor++;
      }
    }
    if (cursor >= statementEnd) continue;
    final rest = text.substring(cursor - from, statementEnd - from);
    final head = _memberHead.firstMatch(rest);
    out.add(
      _Member(
        cursor,
        head?.group(2) ?? '',
        head?.group(1),
        {for (final a in annotations) ..._envFromAnnotation(a)},
      ),
    );
  }
  return out;
}

/// The offset of the bracket closing the one at [open], or -1.
int _matching(String code, int open, String openChar, String closeChar) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == openChar) {
      depth++;
    } else if (c == closeChar) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

bool _isWord(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    unit == 0x24;

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;
