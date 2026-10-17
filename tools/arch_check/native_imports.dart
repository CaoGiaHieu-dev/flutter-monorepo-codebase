import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shared/contract_scan.dart' show packageRootOf;
import 'dart_source.dart';
import 'platform_forks.dart';

/// R22 — native-only libraries stay behind a configurable import (RULE-82).
///
/// A package that may link on the web (its pubspec declares no `platforms:`,
/// or `platforms:` lists `web`) must not import a library the web cannot
/// compile or run from an ordinary `lib/` file: every web build of an app
/// that links the package then fails — `dart:ffi` is a compile error — while
/// `flutter analyze` stays clean, because the analyzer resolves for the VM.
///
/// Such an import is allowed only in the **native target of a configurable
/// import** — a URI of it that no web build loads — that sits in a file of
/// the same package listed in [kPlatformForkAllowList]: the compiler then
/// picks the other side for the web, and the fork is reviewed with its
/// reason. Which side is native is read from the conditions, not from the
/// position: `import 'native.dart' if (dart.library.js_interop) 'web.dart'`
/// and `import 'web.dart' if (dart.library.io) 'native.dart'` both name
/// `native.dart` ([webMayLoad]). Every URI a web build may load is judged,
/// a configuration's as well as the default. Test files are not read.
///
/// File-level only: what the file imports, not what is reachable from it.

/// The libraries no web build can use, and why.
const Map<String, String> kNativeOnlyLibraries = {
  'dart:ffi': 'needs FFI, which no browser has',
  'package:drift/native.dart': 'uses dart:ffi',
  'package:sqlite3/sqlite3.dart':
      'uses dart:ffi — the web uses package:sqlite3/wasm.dart',
  'package:path_provider/path_provider.dart':
      'has no web implementation: MissingPluginException at run time',
};

/// One import R22 reports.
class NativeImportProblem {
  const NativeImportProblem(this.rel, this.line, this.library, this.message);

  /// Repo-relative POSIX path of the importing file.
  final String rel;
  final int line;

  /// The native-only library (a key of [kNativeOnlyLibraries]).
  final String library;

  /// The whole message, starting with `<rel>:<line>:`.
  final String message;
}

/// The R22 problems among [files] (repo-relative POSIX paths) under [root].
///
/// Only `lib/` files of packages under `platform/` or `modules/` are read;
/// [allowList] is R17's list (the files whose configurable imports may name a
/// native-only default target).
List<NativeImportProblem> nativeImportProblems(
  String root,
  Iterable<String> files, {
  Map<String, String> allowList = kPlatformForkAllowList,
}) {
  final rootPosix = p.posix.normalize(root.replaceAll(r'\', '/'));
  final packages = <String, _Package?>{};
  final out = <NativeImportProblem>[];

  for (final rel in files) {
    if (!rel.endsWith('.dart')) continue;
    final segments = p.posix.split(rel);
    if (segments.first != 'platform' && segments.first != 'modules') continue;
    if (!segments.contains('lib')) continue;

    final abs = p.posix.join(rootPosix, rel);
    final pkgDir = packageRootOf(abs, rootPosix);
    final pkg = packages.putIfAbsent(
      pkgDir,
      () => _Package.read(rootPosix, pkgDir, allowList),
    );
    if (pkg == null || !pkg.mayLinkOnWeb) continue;
    // Only the package's own lib/: test/, tool/, web/ are not linked.
    final inPkg = p.posix.relative(abs, from: pkgDir);
    if (!inPkg.startsWith('lib/')) continue;
    if (pkg.allowedTargets.contains(rel)) continue;

    final String source;
    try {
      source = File(abs).readAsStringSync();
    } on FileSystemException {
      continue;
    }
    for (final directive in DartSource.scan(source).directives) {
      if (directive.keyword == 'part') continue;
      final onWeb = webMayLoad(directive);
      for (var i = 0; i < directive.uris.length; i++) {
        // A URI no web build loads is the native side of the fork.
        if (!onWeb[i]) continue;
        final uri = directive.uris[i];
        final reason = kNativeOnlyLibraries[uri];
        if (reason == null) continue;
        out.add(
          NativeImportProblem(
            rel,
            directive.line,
            uri,
            '$rel:${directive.line}: imports $uri, which $reason — every web '
            'build of an app that links ${pkg.name} fails while flutter '
            'analyze stays clean. Reach it through a configurable import '
            'whose file is in kPlatformForkAllowList (as core_database\'s '
            'database_connection_factory.dart does), keep it in test/, or '
            "declare the package's platforms: without web (RULE-82)",
          ),
        );
      }
    }
  }
  return out;
}

/// The `dart.library.<x>` names that every web build has (`dart:js_interop`
/// and the `dart:html` family): a configuration testing one is what the web
/// picks, so neither a later configuration nor the default URI loads there.
const Set<String> kWebLibraries = {
  'html',
  'indexed_db',
  'js',
  'js_interop',
  'js_interop_unsafe',
  'js_util',
  'svg',
  'ui_web',
  'web_audio',
  'web_gl',
};

/// The `dart.library.<x>` names that no web build has: a configuration
/// testing one is never loaded on the web.
const Set<String> kNonWebLibraries = {'cli', 'ffi', 'io', 'isolate'};

/// For each URI of [directive] — `uris[0]`, the default, then each
/// configuration's — whether a web build may load it.
///
/// The compiler takes the first configuration whose test holds, else the
/// default. On the web, a `dart.library.<x>` test of [kWebLibraries] holds
/// and one of [kNonWebLibraries] does not. Any other test (another library,
/// an `== 'value'` comparison, an environment name) is not known here, so
/// its URI may load and the URIs after it stay reachable.
List<bool> webMayLoad(Directive directive) {
  final out = List<bool>.filled(directive.uris.length, false);
  var reached = true;
  for (var i = 1; i < directive.uris.length; i++) {
    final condition = i - 1 < directive.conditions.length
        ? directive.conditions[i - 1]
        : '';
    final onWeb = _holdsOnWeb(condition);
    if (onWeb == false) continue;
    out[i] = reached;
    if (onWeb == true) reached = false;
  }
  out[0] = reached;
  return out;
}

/// Whether [condition] holds on every web build (`true`), on none
/// (`false`), or is not known here (`null`).
bool? _holdsOnWeb(String condition) {
  const prefix = 'dart.library.';
  if (!condition.startsWith(prefix)) return null;
  final library = condition.substring(prefix.length);
  if (kWebLibraries.contains(library)) return true;
  if (kNonWebLibraries.contains(library)) return false;
  return null;
}

/// What R22 needs to know of one package.
class _Package {
  _Package(this.name, this.mayLinkOnWeb, this.allowedTargets);

  final String name;

  /// No `platforms:` in the pubspec, or `platforms:` lists `web`.
  final bool mayLinkOnWeb;

  /// Repo-relative paths of the native targets — the URIs no web build
  /// loads ([webMayLoad]) — of the configurable directives in this package's
  /// allow-listed files.
  final Set<String> allowedTargets;

  /// Null when [pkgDir] holds no readable pubspec (not a package R22 judges).
  static _Package? read(
    String root,
    String pkgDir,
    Map<String, String> allowList,
  ) {
    final pubspec = File(p.posix.join(pkgDir, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final Object? doc;
    try {
      doc = loadYaml(pubspec.readAsStringSync());
    } on YamlException {
      return null;
    }
    if (doc is! YamlMap) return null;
    final name = '${doc['name'] ?? p.posix.basename(pkgDir)}';
    final platforms = doc['platforms'];
    final mayLinkOnWeb = switch (platforms) {
      null => true,
      YamlMap() => platforms.containsKey('web'),
      YamlList() => platforms.contains('web'),
      _ => true,
    };

    final allowed = <String>{};
    final pkgRel = p.posix.relative(pkgDir, from: root);
    final ownPackage = 'package:$name/';
    for (final rel in allowList.keys) {
      if (!p.posix.isWithin(p.posix.join(pkgRel, 'lib'), rel)) continue;
      final file = File(p.posix.join(root, rel));
      if (!file.existsSync()) continue;
      for (final directive in DartSource.scan(
        file.readAsStringSync(),
      ).directives) {
        if (directive.keyword == 'part' || directive.uris.length < 2) continue;
        final onWeb = webMayLoad(directive);
        for (var i = 0; i < directive.uris.length; i++) {
          if (onWeb[i]) continue;
          final uri = directive.uris[i];
          final String target;
          if (uri.startsWith(ownPackage)) {
            target = p.posix.join(
              pkgRel,
              'lib',
              uri.substring(ownPackage.length),
            );
          } else if (uri.contains(':')) {
            continue;
          } else {
            target = p.posix.normalize(
              p.posix.join(p.posix.dirname(rel), uri),
            );
          }
          allowed.add(target);
        }
      }
    }
    return _Package(name, mayLinkOnWeb, allowed);
  }
}
