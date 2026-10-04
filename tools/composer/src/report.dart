import 'catalog.dart';
import 'facts_emit.dart';
import 'manifest_v2.dart';
import 'package_facts.dart';
import 'platform_notes.dart';
import 'profile_summary.dart';

/// The app report: what a newcomer reads first, generated from the manifest and
/// the composed packages.
///
/// It lands between `<!-- composer:managed:report -->` markers in
/// `apps/<id>/README.md` (committed, drift-checked by `composer verify`) and on
/// stdout through `composer describe --app <id>`. It answers five questions —
/// identity (b), platforms (c), composition (a), what the shell resolves (d)
/// and what the app may intervene in (e) — from the same [AppView] the
/// generated facts come from, so the page and the code cannot disagree.
///
/// A backticked repo path in the output would be checked by `docs_check` (the
/// report is Markdown), so a path that may not exist — a runner folder of a
/// `scaffold` platform — appears only inside the `flutter create` command
/// block, never as a span.

/// One check or problem code, as `describe --catalog` lists it.
class CodedLine {
  const CodedLine(this.id, this.what);

  final String id;
  final String what;
}

/// What `composer verify` holds an app to. V1 lives in the parser and V13 in
/// the drift pass; the rest are in `checks.dart`.
const List<CodedLine> kComposerChecks = [
  CodedLine(
    'V1',
    'closed vocabularies, types and ranges; an unknown key; `app.kind` (removed)',
  ),
  CodedLine(
    'V2',
    'every optional contract in the catalog has a declared state; no unknown id',
  ),
  CodedLine(
    'V3',
    '`capabilities:` equals what the composed packages and the app register, both directions; every required contract has an implementer',
  ),
  CodedLine('V4', 'the members of a bundle share one state'),
  CodedLine('V5', '`splash: dart` needs capability `splash` provided'),
  CodedLine(
    'V6',
    '`runner: committed` needs the platform folder; `scaffold` needs it absent',
  ),
  CodedLine(
    'V7',
    'every package the app links that declares `platforms:` supports every platform the app declares',
  ),
  CodedLine(
    'V8',
    '`push: true` needs core_notifications composed and supporting the platform; `window` only on a desktop platform',
  ),
  CodedLine(
    'V9',
    'a pin decision per flavor where a declared platform can pin, refused where none can; pins well-formed',
  ),
  CodedLine(
    'V10',
    'what a composed package needs the app to register (`FirebaseOptions` per flavor) is registered under the app\'s lib/',
  ),
  CodedLine(
    'V11',
    'the env files that exist hold exactly the keys `env:` declares',
  ),
  CodedLine(
    'V12',
    'the entry point passes `profile:`; test/di_smoke_test.dart exists, calls checkAppContract and builds every factory (`FactoryRecorder` + `buildEvery`)',
  ),
  CodedLine(
    'V13',
    'the generated regions (facts, report, imports, modules) equal regeneration; injection.dart holds only comments and blank lines outside its two regions',
  ),
  CodedLine('V14', 'no reason is empty, `TODO` or `TBD`'),
  CodedLine(
    'V15',
    'a committed Android runner has a productFlavor, and a committed iOS runner a scheme with Debug-/Release-/Profile- configurations, for every declared flavor and none the manifest does not declare; no env file exists for an undeclared one (V11)',
  ),
  CodedLine(
    'V16',
    'every DI group has a `why`, and the groups the template names (core, notifications, shell, ui, domain, data, feature, other) keep that relative order',
  ),
  CodedLine(
    'V17',
    'the repository root is the only workspace node: no other pubspec.yaml has a top-level `workspace:` key (RULE-16)',
  ),
];

/// The problem codes the kernel (`validate`, P) and the shell
/// (`checkAppContract`, C) report; a tools test keeps the list equal to them.
const List<CodedLine> kBootProblems = [
  CodedLine(
    'P01',
    'the platform the app runs on is not declared under `platforms:`',
  ),
  CodedLine('P02', 'the flavor is not declared under `flavors:`'),
  CodedLine(
    'P03',
    'an env key `required_in` this flavor is empty (non-debug builds)',
  ),
  CodedLine(
    'P04',
    'no pin decision for this flavor on a platform that can pin',
  ),
  CodedLine(
    'P05',
    'a `window` is declared and no `configureWindow` hook is set',
  ),
  CodedLine('C01', 'a required contract is not registered'),
  CodedLine('C02', 'declared provided, but nothing registers it'),
  CodedLine('C03', 'declared absent, but something registers it'),
  CodedLine('C04', 'the members of a bundle disagree'),
  CodedLine('C05', 'no route and no tab: the app shows nothing'),
  CodedLine('C06', 'two navigation tabs share an `order` (RULE-24)'),
  CodedLine('C07', '`AppRouter.router` failed to assemble'),
  CodedLine('C08', '`DioFailureClassifier` is not registered exactly once'),
  CodedLine(
    'C09',
    'a catalog contract is missing from `facts.capabilities`: run `composer sync`',
  ),
  CodedLine(
    'C10',
    'resolving a registered contract threw: its constructor or factory fails',
  ),
  CodedLine(
    'C11',
    '`router.fallbackPath` is not a route the assembled router registers',
  ),
  CodedLine(
    'C12',
    'two or more navigation tabs and no dashboard: no way to switch between them',
  ),
];

/// The report for [view], Markdown, without the region markers.
String renderReport(AppView view) {
  final decl = view.declaration;
  final derived = derivePlatforms(view);
  final ssl = deriveSslDecisions(view);
  final b = StringBuffer();
  void line([String text = '']) => b.writeln(text);

  line('## ${view.id} — ${decl.name}');
  line(
    'Entry point `${decl.entrypoint}` · generated by '
    '`dart tools/composer/composer.dart sync --app ${view.id}` from '
    '`${view.manifestPath}` · do not edit this block; the same text is '
    'printed by `dart tools/composer/composer.dart describe --app ${view.id}`.',
  );
  line();

  // -- 1. identity ---------------------------------------------------------
  line('### 1. Identity (b)');
  final androidIds = view.native.android;
  final iosIds = view.native.ios;
  line(
    '| Flavor | Env file | SSL pinning |'
    '${androidIds == null ? '' : ' Android application ID |'}'
    '${iosIds == null ? '' : ' iOS bundle ID |'}',
  );
  line(
    '|:--|:--|:--|'
    '${androidIds == null ? '' : ':--|'}'
    '${iosIds == null ? '' : ':--|'}',
  );
  for (final flavor in decl.flavors.keys) {
    final decision = ssl[flavor];
    final String pinning;
    if (decision == null) {
      pinning = 'n/a — no declared platform can pin TLS';
    } else if (decision.value.isPinned) {
      final n = decision.value.pins!.length;
      pinning = 'pinned ($n pins)';
    } else {
      final why = _cell(decision.value.disabledReason!);
      pinning = decision.source == 'manifest'
          ? 'disabled — $why'
          : 'disabled (default) — $why';
    }
    String nativeId(Map<String, String?>? ids) =>
        ids == null ? '' : ' ${_nativeId(ids, flavor)} |';
    line(
      '| $flavor | `${kEnvFiles[flavor]}` | $pinning |'
      '${nativeId(androidIds)}${nativeId(iosIds)}',
    );
  }
  line();
  if (androidIds != null || iosIds != null) {
    line(
      'The application and bundle IDs are read from the committed native '
      'projects (`composer verify` holds their flavor names to the manifest, '
      'check V15; the IDs themselves are not checked).',
    );
    line();
  }
  // Two names exist; say which one a user sees (RULE-80: one owner per value).
  final nameKey = decl.env.any((e) => e.key == 'APP_NAME');
  line(
    'Name shown to users (the MaterialApp title: task switcher and browser tab): '
    '`${decl.name}` (`app.name`)'
    '${nameKey ? ', unless the build defines `APP_NAME`, which overrides it per flavor (`env.<flavor>`, for example `${decl.name} (DEV)`) so a flavor tells itself apart on a device' : ''}.',
  );
  line();
  if (decl.env.isEmpty) {
    line('No environment keys are declared.');
  } else {
    line('| Env key | Read by | Required in |');
    line('|:--|:--|:--|');
    for (final e in decl.env) {
      final readBy = e.nativeOnly
          ? 'native only (Gradle / Xcode) — no Dart reader'
          : 'Dart (`String.fromEnvironment`)';
      final required = e.requiredIn.isEmpty ? '—' : e.requiredIn.join(', ');
      line('| `${e.key}` | $readBy | $required |');
    }
  }
  line();

  // -- 2. platforms --------------------------------------------------------
  line('### 2. Platforms (c) — effective values, `value (source)`');
  line(
    '| Platform | Runner | Splash | Push | Deep links | Orientation | '
    'TLS pinning | Window |',
  );
  line('|:--|:--|:--|:--|:--|:--|:--|:--|');
  for (final platform in derived) {
    line(
      '| ${platform.name} '
      '| ${platform.runner.value} (${platform.runner.source}) '
      '| ${platform.splash.value} (${_cell(platform.splash.source)}) '
      '| ${platform.push.value ? 'on' : 'off'} '
      '(${_cell(platform.push.source)}) '
      '| ${platform.deepLinks.value ? 'on' : 'off'} '
      '(${platform.deepLinks.source}) '
      '| ${_orientation(platform.orientation.value)} '
      '(${platform.orientation.source}) '
      '| ${_tls(platform.name)} '
      '| ${_window(platform.window)} |',
    );
  }
  line();

  final scaffold = [
    for (final p in derived)
      if (p.runner.value == 'scaffold') p.name,
  ];
  if (scaffold.isNotEmpty) {
    line(
      'The runner of ${scaffold.join(', ')} is not in the repository. Create '
      'it once, from the app directory, then declare it `runner: committed`:',
    );
    line();
    line('```bash');
    line('cd ${view.dir}');
    line(
      'flutter create --platforms=${scaffold.join(',')} --org com.example '
      '--project-name ${view.pubspecName} .',
    );
    for (final cleanup in kFlutterCreateCleanup) {
      line(cleanup);
    }
    line('```');
    line();
    line('Native notes (not checked):');
    for (final name in scaffold) {
      for (final note in kPlatformNotes[name] ?? const <String>[]) {
        line('- **$name** — $note');
      }
    }
    line();
  }

  final declared = {for (final p in derived) p.name};
  line('Not targeted — and what blocks it:');
  for (final name in kPlatformNames) {
    if (declared.contains(name)) continue;
    final blockers = <String>[];
    for (final entry in view.packageFacts.entries) {
      final facts = entry.value;
      if (!facts.supports(name)) blockers.add(entry.key);
    }
    if (blockers.isEmpty) {
      line(
        '- **$name** — no composed package blocks it; declare it under '
        '`platforms:` and add its runner.',
      );
    } else {
      line(
        '- **$name** — ${blockers.join(', ')} '
        '${blockers.length == 1 ? 'does' : 'do'} not support it '
        '(`platforms:` in the package pubspec).',
      );
    }
  }
  line();

  // -- 3. composition ------------------------------------------------------
  line('### 3. Composition, in boot order (a)');
  line('| # | Group (phase) | Packages | Why |');
  line('|:-:|:--|:--|:--|');
  var n = 0;
  for (final group in view.groups) {
    n++;
    line(
      '| $n | ${group.name} (${group.phase}) | ${group.packages.join(', ')} '
      '| ${_cell(group.why ?? '')} |',
    );
  }
  line();
  line(
    'Modules: ${view.modules.map((m) => '${m.id} (${m.layers.join(', ')})').join(' · ')}.',
  );
  line();
  final provides = <String>[];
  for (final name in view.composed.toList()..sort()) {
    final facts = view.packageFacts[name];
    for (final need in facts?.appProvides ?? const <AppProvides>[]) {
      final where = need.perFlavor
          ? 'one registration per flavor (${decl.flavors.keys.join(', ')})'
          : 'one registration';
      final hint = need.hint.replaceAll('<id>', view.id);
      provides.add(
        '- `${need.type}` for `$name`: $where.'
        '${hint.isEmpty ? '' : ' $hint.'}',
      );
    }
  }
  if (provides.isEmpty) {
    line('**This app must provide:** nothing beyond its composition.');
  } else {
    line('**This app must provide:**');
    for (final p in provides) {
      line(p);
    }
    line();
    line(
      'The DI smoke test boots every flavor, so a missing registration fails '
      'it with "<Type> is not registered".',
    );
  }
  line();

  // -- 4. what the shell resolves -----------------------------------------
  line('### 4. What the shell resolves from this app (d)');
  line('| Capability | Contract | Need | State | Implemented by | If absent |');
  line('|:--|:--|:--|:--|:--|:--|');
  for (final row in view.catalog.requiredRows) {
    line(
      '| `${row.id}` | `${row.type}` | **required** | registered by the '
      'shell\'s own packages | ${_implementedBy(view, row.type)} '
      '| ${_cell(row.whenAbsent)} |',
    );
  }
  for (final row in view.catalog.optional) {
    final state = view.capability(row.id);
    final stateText = state == null
        ? 'undeclared'
        : state.provided
        ? 'provided'
        : '**absent** — ${_cell(state.reason ?? '')}';
    line(
      '| `${row.id}` | `${row.type}` | optional | $stateText '
      '| ${_implementedBy(view, row.type)} | ${_cell(row.whenAbsent)} |',
    );
  }
  line();
  line(
    'The shell\'s catalog is `SHELL_CONTRACTS` in `platform_app_shell`; a '
    'required row is registered by a shell package, an optional one by an app '
    'or a module, and `checkAppContract` holds this table to the graph the app '
    'actually builds. `ISessionStatusStream` has no row: only a module looks '
    'it up. "Implemented by" is a static scan of the composed packages and '
    'this app\'s own source for a registration of the exact type '
    '(`composer verify` holds it to the state above, check V3); a hand-written '
    '`getIt.register…` is invisible to it, which is why `checkAppContract` '
    'stays the authority.',
  );
  line();

  // -- 5. behaviour values -------------------------------------------------
  line('### 5. Behaviour values (profile)');
  line(
    'Typed Dart in `lib/app/app_profile.dart`, below the generated facts: '
    'five sections, each documenting its ranges. A section the app leaves out '
    'is the template default printed here; a section it sets is printed as '
    'written (`composer verify` re-reads the file, so this page cannot go '
    'stale).',
  );
  line();
  final profile = view.profile;
  if (!profile.found) {
    line(
      'The app\'s `lib/app/app_profile.dart` was not found, so every value is '
      'shown as the template default.',
    );
  } else if (profile.expressions.isEmpty) {
    line(
      '**This app sets no profile section: every value below is the template '
      'default.**',
    );
  } else {
    line(
      '**This app sets: ${profile.expressions.keys.map((k) => '`$k:`').join(', ')}.** '
      'The other sections are the template default.',
    );
  }
  line();
  line('| Section | What it tunes | This app | Template default |');
  line('|:--|:--|:--|:--|');
  for (final section in kProfileSections) {
    final set = profile.expressions[section.key];
    final defaults = [
      for (final d in section.defaults)
        d == 'languages: every language the template ships'
            ? (view.shippedLanguages.isEmpty
                  ? d
                  : 'languages: every language the template ships '
                        '(${view.shippedLanguages.join(', ')})')
            : d,
    ];
    line(
      '| `${section.key}:` (`${section.type}`) | ${_cell(section.tunes)} '
      '| ${set == null ? 'default' : '**set** — `${_cell(set)}`'} '
      '| ${_cell(defaults.join(' · '))} |',
    );
  }
  line();

  // -- 6. decisions to revisit ----------------------------------------------
  line('### 6. Decisions to revisit before shipping');
  final revisit = <String>[];
  for (final entry in ssl.entries) {
    final decision = entry.value.value;
    if (entry.key != 'dev' && !decision.isPinned) {
      revisit.add(
        '`flavors.${entry.key}.ssl_pinning`: **disabled** — '
        '${_cell(decision.disabledReason!)}',
      );
    }
  }
  final listed = <String>{};
  void revisitAbsent(String key, CapabilityDecl? state) {
    if (state == null || state.provided || !listed.add(key)) return;
    revisit.add(
      '`capabilities.$key`: **absent** — ${_cell(state.reason ?? '')}',
    );
  }

  // A crash reporter and analytics are worth a second look on every app; any
  // other absence is listed while its reason is still `new`'s placeholder.
  for (final id in const ['error_reporter', 'analytics']) {
    revisitAbsent(id, view.capability(id));
  }
  for (final row in view.catalog.optional) {
    final state = view.capability(row.id);
    if (state != null &&
        !state.provided &&
        (state.reason ?? '').startsWith(kNotComposedPrefix)) {
      revisitAbsent(row.manifestKey, state);
    }
  }
  if (revisit.isEmpty) {
    line('None.');
  } else {
    for (final item in revisit) {
      line('- $item');
    }
  }
  line();

  // -- 7. extension points --------------------------------------------------
  line('### 7. Extension points (e)');
  line(
    'Channels: manifest sections (`platforms`, `capabilities`, `flavors`, '
    '`env`, `di_groups`, `modules`) · the profile (`lib/app/app_profile.dart`) '
    '· hooks (`lib/app/app_hooks.dart`, type `const ShellHooks(`: the error '
    'channels, `beforeDependencies`, `afterBoot`, `navigatorObservers`, '
    '`redirect`, `configureWindow`) · contracts the app registers under '
    '`lib/app/`.',
  );
  line();
  line(
    '**Locked** — changing one means editing the shared package, for every '
    'app: the shadow and scrim colours, breakpoints, component themes, page '
    'transitions, the default '
    'interceptor chain, the 404 page, push channel and icon, deep-link '
    'allow-lists, logger limits, system UI overlay, secure-storage options. '
    'Replacing a shell-owned type by registration order is unsupported: the '
    'first registration of a type wins (GetIt, '
    '`enableRegisteringMultipleInstancesOfOneType`), which works only for '
    'types registered in the `after` groups.',
  );
  return b.toString();
}

/// The native ID of [flavor] in [ids], or `—`.
String _nativeId(Map<String, String?> ids, String flavor) {
  if (!ids.containsKey(flavor)) return '—';
  final id = ids[flavor];
  return id == null ? '— (not readable)' : '`$id`';
}

/// The packages of the app's graph that register [type], or `—`; the app's own
/// source is `this app`.
String _implementedBy(AppView view, String type) {
  final names = {
    for (final provision in view.providersOf(type))
      provision.package == view.pubspecName ? 'this app' : provision.package,
  }.toList()..sort();
  return names.isEmpty ? '—' : names.join(', ');
}

/// What the kernel's `OrientationPolicy` constant [policy] does.
String _orientation(String policy) => switch (policy) {
  'phonesPortrait' => 'phone-sized displays portrait, larger free',
  'free' => 'free',
  'portrait' => 'always portrait',
  'landscape' => 'always landscape',
  _ => policy,
};

/// The declared window of a platform, or `—`.
String _window(Sourced<WindowDecl>? window) {
  if (window == null) return '—';
  final decl = window.value;
  final min = decl.min == null
      ? ''
      : ', min ${decl.min!.width} x ${decl.min!.height}';
  return '${decl.initial.width} x ${decl.initial.height}$min '
      '(${window.source}; needs the `configureWindow` hook)';
}

String _tls(String platform) {
  if (kPinnablePlatforms.contains(platform)) {
    return 'can pin (decision per flavor, §1)';
  }
  if (platform == 'web') return 'n/a (the browser owns TLS)';
  return 'n/a (the pinning plugin has no implementation here)';
}

/// [text] safe inside a Markdown table cell.
String _cell(String text) => text.replaceAll('|', r'\|').replaceAll('\n', ' ');

/// `describe --catalog`: the manifest schema (the parse table), the shell's
/// contract catalog and the derived defaults — the three things a manifest
/// author looks up, printed from the same data the tool validates against.
String renderCatalog(ShellCatalog catalog) {
  final b = StringBuffer();
  void line([String text = '']) => b.writeln(text);

  line('MANIFEST KEYS (app_manifest.yaml)');
  line('A key exists only together with the code that reads it.');
  line();
  for (final key in kManifestKeys) {
    line('  ${key.key}');
    line('      type        ${key.type}');
    line('      default     ${key.defaultValue}');
    line('      refused     ${key.validation}');
    line(
      key.reportOnly
          ? '      read by     ${key.consumer} (${key.reads}) — composer only: '
                'a check and the report read it; no runtime code does, so it '
                'is carried in the generated facts for tests and `describe`'
          : '      read by     ${key.consumer} (${key.reads})',
    );
    line('      replaces    ${key.replaces}');
    line();
  }
  line(
    '  Composition keys (di_groups, modules, extra_dependencies) are '
    'unchanged: see `composer --help`.',
  );
  line();

  line('SHELL CONTRACTS (what `capabilities:` declares)');
  line(
    'A bundle id declares all its members at once; they share one state. '
    'A required row is registered by the shell\'s own packages and needs no '
    'declaration.',
  );
  line();
  line(
    '  ${'id'.padRight(20)} ${'need'.padRight(9)} ${'bundle'.padRight(8)} contract',
  );
  for (final row in catalog.entries) {
    line(
      '  ${row.id.padRight(20)} ${(row.required ? 'required' : 'optional').padRight(9)} '
      '${(row.bundle ?? '').padRight(8)} ${row.type}'
      '${row.many ? ' (many)' : ''}',
    );
  }
  line();
  line('  Where the shell looks each one up, and what it does without it:');
  for (final row in catalog.entries) {
    line('    ${row.id}');
    line('        looked up at  ${row.consumer}');
    line(
      '        if absent     '
      '${row.required ? 'the shell\'s own packages register it, so: ' : ''}'
      '${row.whenAbsent}',
    );
  }
  line();

  line('DERIVED DEFAULTS (what the generated facts fill in)');
  line(
    '  TLS pinning can apply on   ${kPinnablePlatforms.join(', ')} '
    '(web: the browser owns TLS; desktop: the pinning plugin has no '
    'implementation)',
  );
  line(
    '  splash                     ios: native; elsewhere dart when '
    'capability splash is provided, else native',
  );
  line(
    '  push                       on when core_notifications is composed '
    'and supports the platform; off on web (no service worker is shipped)',
  );
  line('  deep links                 on');
  line(
    '  orientation                phones_portrait: displays under the phone '
    'threshold locked to portrait',
  );
  line('  window                     none: the shell does not touch it');
  line(
    '  (every platform key above can be set in the manifest; what it sets is '
    'printed with `manifest` as its source)',
  );
  line('  ssl_pinning, dev flavor    disabled — "$kDevPinReason"');
  line();

  line('PACKAGE KEYS (pubspec.yaml of a package an app composes)');
  line(
    'Dart-native keys pub accepts and validates nothing about, so composer '
    'does (checks V7 and V10).',
  );
  line();
  line('  platforms: [android, ios, ...]');
  line(
    '      where the package works: ${kPlatformNames.join(', ')}; left out, '
    'everywhere. An app that declares a platform a composed package '
    '(or one it links through another) does not list is refused.',
  );
  line('  composition.app_provides.<Type>: { per_flavor: bool, hint: "..." }');
  line(
    '      what the package needs the app to register itself. per_flavor: an '
    '@Environment(\'<flavor>\') registration for every declared flavor. '
    'The hint says where and how; it is printed in the app report.',
  );
  line();

  line('CHECKS (`composer verify`, CI Gate 0)');
  for (final check in kComposerChecks) {
    line('  ${check.id.padRight(4)} ${check.what}');
  }
  line(
    '  Each prints `<file>: <key>: <problem>` with the line to paste. The scan '
    'behind V3, V10 and the report\'s "implemented by" column reads source, '
    'not the graph: `checkAppContract` stays the authority.',
  );
  line();

  line('PROBLEM CODES (boot, and `checkAppContract` in the smoke test)');
  for (final code in kBootProblems) {
    line('  ${code.id.padRight(4)} ${code.what}');
  }
  line(
    '  Each prints `Description:` and `Action:`, the action paste-ready. A dev '
    'or staging flavor, or a debug build, stops at the boot-error screen; a '
    'production release logs an ERROR and reports it non-fatally.',
  );
  line();

  line('NEW APP');
  line(
    '  composer new <id> --platforms <a,b> [--modules <x,y>] [--name "<text>"] '
    'renders tools/composer/app_template/ into apps/<id>/, derives '
    '`capabilities:` from what the modules register (an absent contract '
    'carries what the shell does without it as its reason), then runs sync '
    'and verify. It refuses an id that exists or a platform a module blocks '
    'before writing, and prints the `flutter create` line instead of running '
    'it.',
  );
  return b.toString();
}
