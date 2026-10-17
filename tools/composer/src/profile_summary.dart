import 'dart:io';

import 'package:path/path.dart' as p;

/// What the app report says about the profile sections — the typed Dart an app
/// writes in `lib/app/app_profile.dart` (`DisplayProfile`, `RouterProfile`,
/// `LocaleProfile`, `ThemeProfile`, `NetworkProfile`).
///
/// composer runs before code generation and cannot evaluate Dart, so it does
/// two cheap things instead of printing a paragraph that is the same for every
/// app:
///
///  1. it spells the **template defaults** of each section here, in words, and
///     `app_sync_test.dart` holds every number in them to the kernel source
///     that declares it — so a default changed there fails a test here;
///  2. it reads which sections the app's own `appProfile` **sets** (the named
///     arguments of the `AppProfile(` call) and prints their source, so a
///     reader sees at once whether this app is the template or tuned, and how.
///
/// The report is drift-checked (`composer verify`, V13): tuning a section
/// without regenerating the page fails Gate 0, so the page cannot go stale.
class ProfileSection {
  const ProfileSection({
    required this.key,
    required this.type,
    required this.tunes,
    required this.defaults,
  });

  /// The named argument of `AppProfile(` (`display`).
  final String key;

  /// The section's Dart type (`DisplayProfile`).
  final String type;

  /// What it tunes, a few words.
  final String tunes;

  /// What the template does when the section is left out: each entry is one
  /// effective value.
  final List<String> defaults;
}

/// The design size of the template's artboard.
const String kDefaultDesignSize = '375 x 812';

/// The OS font-size cap the template honours.
const String kDefaultTextScaleMax = '2.0';

/// The shortest side under which `phones_portrait` locks a display to
/// portrait.
const String kDefaultPhoneMax = '600 dp';

/// The default timeout of each of the default HTTP client's phases.
const String kDefaultTimeout = '20 s';

/// The tunable profile sections, with their template defaults.
const List<ProfileSection> kProfileSections = [
  ProfileSection(
    key: 'display',
    type: 'DisplayProfile',
    tunes:
        'the design artboard, the scale policy of each window class, the '
        'OS font-size cap',
    defaults: [
      'design size $kDefaultDesignSize',
      'OS text-scale cap $kDefaultTextScaleMax',
      'split-screen mode on',
      'scale: the expanded window class is drawn 1:1 (fixed), every other '
          'class scales down only',
      'phone threshold $kDefaultPhoneMax',
    ],
  ),
  ProfileSection(
    key: 'router',
    type: 'RouterProfile',
    tunes: 'when the entry location is used, the fallback location',
    defaults: [
      'entry location: first launch only',
      'fallback location: the first navigation destination, else the '
          'placeholder route of an app with none',
    ],
  ),
  ProfileSection(
    key: 'locale',
    type: 'LocaleProfile',
    tunes: 'the languages offered, the fallback and the first-launch language',
    defaults: [
      'languages: every language the template ships',
      'fallback: en',
      'first launch: the device language when offered, else the fallback',
    ],
  ),
  ProfileSection(
    key: 'theme',
    type: 'ThemeProfile',
    tunes: 'the mode a first launch opens in, the palette overrides',
    defaults: [
      'mode: follows the OS (system)',
      'palette: the template\'s own, light and dark',
    ],
  ),
  ProfileSection(
    key: 'network',
    type: 'NetworkProfile',
    tunes: 'the default HTTP client\'s timeouts, extra headers, redirects, hosts besides the API host that may receive the session token',
    defaults: [
      'connect, receive and send timeout $kDefaultTimeout each',
      'no extra headers',
      'redirects are not followed',
      'the session token goes only to the API host',
    ],
  ),
];

/// The sections an app's `appProfile` sets, from the source of its
/// `lib/app/app_profile.dart`.
class ProfileOverrides {
  const ProfileOverrides(this.expressions, {required this.found});

  /// No `app_profile.dart`, or no `AppProfile(` call in it: nothing is known.
  const ProfileOverrides.unknown() : expressions = const {}, found = false;

  /// Section key -> the argument as written (comments removed, whitespace
  /// collapsed).
  final Map<String, String> expressions;

  /// Whether an `AppProfile(` call was found and read.
  final bool found;

  /// Whether the app sets [key].
  bool sets(String key) => expressions.containsKey(key);
}

/// Reads [source], the text of an app's `app_profile.dart`.
///
/// The one `AppProfile(` call that is not the generated facts' own: the named
/// arguments of the call, at its top level, whose names are profile sections.
ProfileOverrides parseProfileOverrides(String source) {
  final code = _withoutComments(source);
  final call = RegExp(r'\bAppProfile\s*\(').firstMatch(code);
  if (call == null) return const ProfileOverrides.unknown();

  final open = call.end - 1;
  final args = <String, String>{};
  var depth = 0;
  var argStart = open + 1;
  String? name;

  void finish(int end) {
    final text = code.substring(argStart, end).trim();
    if (text.isEmpty) return;
    final m = RegExp(r'^(\w+)\s*:\s*(.*)$', dotAll: true).firstMatch(text);
    if (m == null) return;
    name = m.group(1);
    args[name!] = m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        finish(i);
        break;
      }
    } else if (c == ',' && depth == 1) {
      finish(i);
      argStart = i + 1;
    }
  }

  final known = {for (final section in kProfileSections) section.key};
  return ProfileOverrides({
    for (final entry in args.entries)
      if (known.contains(entry.key)) entry.key: entry.value,
  }, found: true);
}

/// The overrides of the app at [appDir], or [ProfileOverrides.unknown] when it
/// has no `lib/app/app_profile.dart`.
ProfileOverrides readProfileOverrides(String appDir) {
  final file = File(p.join(appDir, 'lib', 'app', 'app_profile.dart'));
  if (!file.existsSync()) return const ProfileOverrides.unknown();
  return parseProfileOverrides(file.readAsStringSync());
}

/// The language codes the template ships, from the `*.arb` files of
/// `core_base_ui`'s `assets/language/` directory (empty when it is not there).
List<String> readShippedLanguages(String? designSystemDir) {
  if (designSystemDir == null) return const [];
  final dir = Directory(p.join(designSystemDir, 'assets', 'language'));
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync())
      if (entity is File && entity.path.endsWith('.arb'))
        p.basenameWithoutExtension(entity.path),
  ]..sort();
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');
