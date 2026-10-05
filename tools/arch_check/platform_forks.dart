import 'dart_source.dart';

/// R17 — a platform difference is an app decision (RULE-82).
///
/// What an app enables on a platform is declared in its manifest and read from
/// `PlatformFacts`; the one place that turns the Flutter runtime into an
/// `AppPlatform` is `resolveAppPlatform()`. A `Platform.isIOS`, `kIsWeb`,
/// `defaultTargetPlatform` or `TargetPlatform.*` anywhere else is a second,
/// private answer to "where am I running" that no manifest can see and no gate
/// can check — the bug class that left a Linux build with a blank window.
///
/// Some forks are not an app decision but the availability of an operating
/// system API (`dart:io`'s `Platform` throws on the web; an OS asks for a
/// notification permission its own way). They are listed here, **each with the
/// reason**, so the exception is visible in review and R17 fails when a listed
/// file stops forking (the entry is then dead) or when a reason is empty.

/// Hand-written Dart that may fork on the platform, and why. Keys are
/// repo-relative POSIX paths.
const Map<String, String> kPlatformForkAllowList = {
  'platform/foundation/common/lib/src/config/platform_resolver.dart':
      'the policy fork itself: resolveAppPlatform() maps kIsWeb and '
      'defaultTargetPlatform to AppPlatform, web first because Platform.* '
      'throws there',
  'platform/foundation/common/lib/src/go_route_data_custom.dart':
      'the page type is an OS convention (CupertinoPage on iOS, MaterialPage '
      'on the web, a Cupertino-style slide elsewhere); every page is wrapped '
      'in RouteAwareWidget on every platform',
  'platform/shell/app_shell/lib/src/main_scope.dart':
      'flutter_native_splash has no web side: FlutterNativeSplash.remove() '
      'throws PlatformException(removeSplashFromWeb) there',
  'platform/ui/design_system/lib/src/theme/theme_provider.dart':
      'PageTransitionsTheme is a table keyed by TargetPlatform: a transition '
      'per OS convention, not a choice an app makes',
};

/// What counts as a fork: the dart:io `Platform` getters, the Flutter web
/// constant and the runtime target.
final RegExp platformFork = RegExp(
  r'\bPlatform\s*\.\s*(?:is[A-Z]\w*|operatingSystem)\b'
  r'|\bkIsWeb\b'
  r'|\bdefaultTargetPlatform\b'
  r'|\bTargetPlatform\s*\.\s*\w+',
);

/// One fork in a source file.
class ForkSite {
  const ForkSite(this.line, this.text);

  final int line;

  /// What matched (`Platform.isIOS`, `kIsWeb`).
  final String text;
}

/// The forks in [scanned] (a file through [DartSource.scan]), so comments and
/// string literals — a doc comment that mentions `kIsWeb` — are not code.
List<ForkSite> forkSitesIn(DartSource scanned) => [
  for (final m in platformFork.allMatches(scanned.code))
    ForkSite(
      scanned.lineOf(m.start),
      m.group(0)!.replaceAll(RegExp(r'\s+'), ''),
    ),
];

/// Problems with the allow-list itself: an entry whose reason says nothing.
List<String> allowListProblems(Map<String, String> allowList) => [
  for (final entry in allowList.entries)
    if (entry.value.trim().length < 12)
      '${entry.key}: an allow-list entry needs a reason that says why this '
          'file may fork on the platform',
];

/// Whether [rel] (repo-relative, POSIX) is hand-written Dart R17 reads: a
/// package's `lib/` under `platform/` or `modules/`, or an app's `lib/`.
bool isForkScanned(String rel) {
  if (!rel.endsWith('.dart')) return false;
  final segments = rel.split('/');
  if (segments.length < 3) return false;
  return switch (segments.first) {
    'platform' || 'modules' => segments.contains('lib'),
    'apps' => segments[2] == 'lib',
    _ => false,
  };
}
