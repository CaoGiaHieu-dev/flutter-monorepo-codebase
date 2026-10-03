import 'dart:io';

import 'package:mustache_template/mustache.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'catalog.dart';
import 'manifest_v2.dart';
import 'package_facts.dart';
import 'provisions.dart';

/// `composer new <id>`: the pieces that need no knowledge of composer's
/// private manifest reader — reading the request, planning the composition,
/// rendering `tools/composer/app_template/`.
///
/// An app is a manifest plus the files composer writes its regions into, so
/// the third app is one command instead of a hand copy of `apps/admin`. The
/// command **never runs `flutter create`**: a runner is native-project state
/// the Flutter tool owns, so the manifest declares each platform
/// `runner: scaffold` and the command prints the line to run.
///
/// The composition is the shape `apps/admin` has — the shared core, shell and
/// ui groups, every layer of the requested modules — and `capabilities:` is
/// *derived* from what those packages register: `provided` where something
/// registers the contract, else `absent` with the catalog's `whenAbsent` text
/// (what the shell does without it) as the reason. Truthful, never `TODO`
/// (V14 refuses it), so the new app passes `verify` at once.
///
/// [composer.dart] runs the manifest it renders through the same parser and
/// checks as any other before a single file is written.

/// Where the app's files are rendered from, relative to the repository root.
const String kAppTemplateDir = 'tools/composer/app_template';

/// Packages every app composes, by group. `core_database` joins `core` only
/// when a requested module links it.
const List<String> kNewCoreBefore = [
  'core_common',
  'core_network',
  'core_storage',
];
const List<String> kNewCoreAfter = ['core_di'];
const String kDatabasePackage = 'core_database';
const List<String> kNewShellPackages = [
  'platform_shell_adapters',
  'platform_app_shell',
  'core_base_ui',
  'domain_core',
  'data_core',
  'provider_state_management',
  'bloc_state_management',
];

/// The layers a module's packages come in, in manifest order.
const List<String> kModuleLayers = ['api', 'domain', 'data', 'feature'];

/// Why the `core` group looks the way it does, as the manifest records it.
const String kCoreWhyPlain =
    'no core_database / core_notifications: this app opens no SQLite file and '
    'sends no push, so it needs no `notifications` group and no lib/firebase/';
const String kCoreWhyDatabase =
    'mechanism only, registered before anything the app or a module adds. '
    'core_database registers nothing: each package that persists data declares '
    'its own database';

/// The reason a staging or prod flavor does not pin yet, on an app that has a
/// platform that can.
const String kNewPinReason =
    'no SPKI pins provisioned yet for this app — decide before shipping '
    '(docs/en/guides/08_networking.md § 10)';

/// What `composer new` was asked for.
class NewAppRequest {
  const NewAppRequest({
    required this.id,
    required this.name,
    required this.platforms,
    required this.modules,
  });

  final String id;
  final String name;

  /// Platform names, canonical order.
  final List<String> platforms;

  /// Module ids, in the order given.
  final List<String> modules;
}

/// Reads `new <id> [--name <text>] --platforms <a,b> [--modules <x,y>]`.
///
/// Throws a [FormatException] saying what is wrong; nothing here touches the
/// disk.
NewAppRequest parseNewArgs(List<String> args) {
  String? id;
  String? name;
  String? platforms;
  String? modules;
  String value(int i, String flag) {
    if (i + 1 >= args.length || args[i + 1].startsWith('-')) {
      throw FormatException('`$flag` needs a value.');
    }
    return args[i + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--name':
        name = value(i, arg);
        i++;
      case '--platforms':
        platforms = value(i, arg);
        i++;
      case '--modules':
        modules = value(i, arg);
        i++;
      default:
        if (arg.startsWith('-')) {
          throw FormatException('Unknown argument `$arg` for `new`.');
        }
        if (id != null) {
          throw FormatException(
            'One app id, please: got `$id` and `$arg`. Platforms and modules '
            'are comma-separated lists: --platforms web,windows',
          );
        }
        id = arg;
    }
  }

  if (id == null) {
    throw const FormatException(
      '`new` needs an app id: dart tools/composer/composer.dart new <id> '
      '--platforms <a,b> [--modules <x,y>] [--name "<Display Name>"]',
    );
  }
  if (platforms == null) {
    throw FormatException(
      '`new` needs `--platforms` — an app that does not say where it runs is '
      'the problem the manifest solves. One or more of '
      '${kPlatformNames.join(', ')}, comma-separated: --platforms web,windows',
    );
  }
  List<String> list(String text) => [
    for (final part in text.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  return NewAppRequest(
    id: id,
    name: name ?? _titleCase(id),
    platforms: list(platforms),
    modules: modules == null ? const [] : list(modules),
  );
}

/// `reports_hub` -> `Reports Hub`.
String _titleCase(String id) => id
    .split('_')
    .where((s) => s.isNotEmpty)
    .map((s) => s[0].toUpperCase() + s.substring(1))
    .join(' ');

/// The contract state `new` writes for one catalog key.
class PlannedCapability {
  const PlannedCapability(this.key, {required this.provided, this.reason});

  final String key;
  final bool provided;

  /// What the shell does without it, for an absent contract.
  final String? reason;
}

/// One requested module and the layers it has on disk.
class PlannedModule {
  const PlannedModule(this.id, this.layers);

  final String id;
  final List<String> layers;
}

/// What `new` will write, decided and checked but not yet rendered.
class NewAppPlan {
  const NewAppPlan({
    required this.request,
    required this.corePackages,
    required this.modules,
    required this.composed,
    required this.capabilities,
    required this.catalog,
  });

  final NewAppRequest request;

  /// The `core` group, in order.
  final List<String> corePackages;
  final List<PlannedModule> modules;

  /// Every package the app will compose.
  final Set<String> composed;
  final List<PlannedCapability> capabilities;
  final ShellCatalog catalog;

  String get id => request.id;
  String get pubspecName => '${request.id}_app';
  bool get usesDatabase => corePackages.contains(kDatabasePackage);

  /// Whether any declared platform can enforce TLS pinning — what decides if
  /// staging and prod must carry a pin decision.
  bool get anyPlatformCanPin =>
      request.platforms.any(kPinnablePlatforms.contains);

  /// The platform the smoke test names: a VM reports Android and never the
  /// web, so a declared platform that is not `web` when there is one.
  String get smokePlatform => request.platforms.firstWhere(
    (name) => name != 'web',
    orElse: () => request.platforms.first,
  );
}

/// Why [request] cannot become an app, or the plan for it.
///
/// Reads the workspace and writes nothing. Every problem is one line, and the
/// caller refuses with all of them.
({NewAppPlan? plan, List<String> problems}) planNewApp({
  required NewAppRequest request,
  required String root,
  required Map<String, String> packages,
  required Set<String> existingIds,
  required ShellCatalog catalog,
  required ProvisionIndex provisions,
  required String? Function(String module, String layer) modulePackage,
}) {
  final problems = <String>[];

  // -- the id ------------------------------------------------------------------
  final id = request.id;
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
    problems.add(
      'app id `$id`: expected lowercase letters, digits and `_`, starting with '
      'a letter — it becomes the folder apps/$id, the package ${id}_app and '
      'every `--app $id`',
    );
  } else {
    if (existingIds.contains(id)) {
      problems.add(
        'app id `$id`: already the id of an app — each app needs its own',
      );
    }
    if (Directory(p.join(root, 'apps', id)).existsSync()) {
      problems.add(
        'apps/$id already exists — `new` creates an app, it never writes into '
        'a folder that is there',
      );
    }
    if (packages.containsKey('${id}_app')) {
      problems.add(
        'the package name `${id}_app` is already taken by '
        '${p.posix.relative(packages['${id}_app']!, from: root)}',
      );
    }
  }

  // -- the name ----------------------------------------------------------------
  if (request.name.trim().isEmpty ||
      RegExp('["\'\\\\\$\\x00-\\x1f]').hasMatch(request.name)) {
    problems.add(
      '--name: expected a display name without quotes, backslashes, `\$` or '
      'line breaks — it is written into YAML, Dart and an env file',
    );
  }

  // -- the platforms -----------------------------------------------------------
  if (request.platforms.isEmpty) {
    problems.add(
      '--platforms: name at least one of ${kPlatformNames.join(', ')}',
    );
  }
  final seen = <String>{};
  for (final platform in request.platforms) {
    if (!kPlatformNames.contains(platform)) {
      problems.add(
        '--platforms: `$platform` is not a platform — expected one of '
        '${kPlatformNames.join(', ')}',
      );
    } else if (!seen.add(platform)) {
      problems.add('--platforms: `$platform` is listed more than once');
    }
  }

  // -- the shared packages -----------------------------------------------------
  final fixed = [
    ...kNewCoreBefore,
    ...kNewCoreAfter,
    ...kNewShellPackages,
  ];
  final absent = [
    for (final name in fixed)
      if (!packages.containsKey(name)) name,
  ];
  if (absent.isNotEmpty) {
    problems.add(
      'the shared packages ${absent.join(', ')} are not in this workspace — '
      'run `new` from the repository root of a full checkout',
    );
  }

  // -- the modules -------------------------------------------------------------
  final modules = <PlannedModule>[];
  final moduleIds = <String>{};
  for (final moduleId in request.modules) {
    if (!moduleIds.add(moduleId)) {
      problems.add('--modules: `$moduleId` is listed more than once');
      continue;
    }
    final layers = [
      for (final layer in kModuleLayers)
        if (modulePackage(moduleId, layer) != null) layer,
    ];
    if (layers.isEmpty) {
      final known = _moduleIdsOnDisk(root);
      problems.add(
        '--modules: no module named `$moduleId` (no package for any of its '
        'layers)${known.isEmpty ? '' : ' — modules here: ${known.join(', ')}'}',
      );
      continue;
    }
    modules.add(PlannedModule(moduleId, layers));
  }

  if (problems.isNotEmpty) return (plan: null, problems: problems);

  // -- the composition ---------------------------------------------------------
  // The packages the groups will hold, from the layers each module has.
  final composedWithoutDatabase = <String>{
    ...kNewCoreBefore,
    ...kNewCoreAfter,
    ...kNewShellPackages,
    for (final module in modules)
      for (final layer in module.layers)
        if (layer != 'api') modulePackage(module.id, layer)!,
  };
  final workspaceOnly = <String>{
    for (final module in modules)
      for (final layer in module.layers)
        if (layer == 'api') modulePackage(module.id, layer)!,
  };

  // What the app links: the composed packages and what they depend on. A module
  // that opens a database reaches `core_database` through its data package.
  final linked = _linkedPackages(
    [...composedWithoutDatabase, ...workspaceOnly],
    packages,
  );
  final reachable = linked.keys.toSet();
  if (reachable.contains('core_notifications')) {
    problems.add(
      'a requested module links core_notifications, which needs the app to '
      'register FirebaseOptions per flavor and a `notifications` group — '
      '`new` does not scaffold push (apps/mobile is the pattern). Create the '
      'app without that module and compose it by hand',
    );
    return (plan: null, problems: problems);
  }

  // A platform a linked package cannot run on is refused here, naming the
  // module that pulled the package in — the same rule as V7, said with the
  // request in hand.
  final ownerOf = <String, String>{
    for (final module in modules)
      for (final layer in module.layers)
        modulePackage(module.id, layer)!: 'module `${module.id}`',
  };
  for (final platform in request.platforms) {
    if (!kPlatformNames.contains(platform)) continue;
    for (final name in linked.keys.toList()..sort()) {
      final link = linked[name]!;
      if (link.facts.supports(platform)) continue;
      final owner = ownerOf[link.chain.first] ?? 'the shared shell';
      problems.add(
        '--platforms: ${link.facts.name} does not support $platform (its '
        'pubspec `platforms:` lists ${link.facts.platforms!.join(', ')}) but '
        '$owner links it (${link.chain.join(' -> ')}) — drop $platform, or '
        'drop the module',
      );
    }
  }
  if (problems.isNotEmpty) return (plan: null, problems: problems);

  final usesDatabase = reachable.contains(kDatabasePackage);
  if (usesDatabase && !packages.containsKey(kDatabasePackage)) {
    problems.add(
      'a requested module needs $kDatabasePackage, which is not in this '
      'workspace',
    );
    return (plan: null, problems: problems);
  }
  final core = [
    ...kNewCoreBefore,
    if (usesDatabase) kDatabasePackage,
    ...kNewCoreAfter,
  ];
  final composed = {
    ...composedWithoutDatabase,
    if (usesDatabase) kDatabasePackage,
  };

  // -- the capabilities --------------------------------------------------------
  // Provided where a composed package registers the exact type, else absent.
  // A bundle is declared once and its members share one state, so a bundle
  // that is registered in part has no truthful single declaration.
  final capabilities = <PlannedCapability>[];
  for (final key in catalog.optionalKeys) {
    final members = catalog.membersOf(key);
    final registered = [
      for (final row in members) provisions.of(row.type, composed).isNotEmpty,
    ];
    if (registered.every((r) => r)) {
      capabilities.add(PlannedCapability(key, provided: true));
    } else if (registered.every((r) => !r)) {
      capabilities.add(
        PlannedCapability(
          key,
          provided: false,
          reason: members.first.whenAbsent,
        ),
      );
    } else {
      final have = [
        for (var i = 0; i < members.length; i++)
          if (registered[i]) members[i].type,
      ];
      problems.add(
        'the requested modules register ${have.join(', ')} but not the rest '
        'of the `$key` bundle — a bundle is one declaration, so compose the '
        'modules that complete it, or drop the one that does not',
      );
    }
  }
  if (problems.isNotEmpty) return (plan: null, problems: problems);

  return (
    plan: NewAppPlan(
      request: request,
      corePackages: core,
      modules: modules,
      composed: composed,
      capabilities: capabilities,
      catalog: catalog,
    ),
    problems: problems,
  );
}

/// Module ids that have a folder under `modules/`.
List<String> _moduleIdsOnDisk(String root) {
  final dir = Directory(p.join(root, 'modules'));
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync())
      if (entity is Directory) p.basename(entity.path),
  ]..sort();
}

/// [seeds] and every workspace package they depend on (`dependencies:` only —
/// the ones linked into the app's build), each with the shortest chain from a
/// seed to it and the package's own facts.
Map<String, ({List<String> chain, PackageFacts facts})> _linkedPackages(
  Iterable<String> seeds,
  Map<String, String> packages,
) {
  final out = <String, ({List<String> chain, PackageFacts facts})>{};
  final queue = <List<String>>[
    for (final seed in seeds) [seed],
  ];
  for (var i = 0; i < queue.length; i++) {
    final chain = queue[i];
    final name = chain.last;
    if (out.containsKey(name)) continue;
    final dir = packages[name];
    if (dir == null) continue;
    final facts = readPackageFacts(
      name,
      dir,
      p.posix.join(dir, 'pubspec.yaml'),
      <String>[],
    );
    out[name] = (chain: chain, facts: facts);
    for (final dependency in facts.dependencies) {
      if (packages.containsKey(dependency) && !out.containsKey(dependency)) {
        queue.add([...chain, dependency]);
      }
    }
  }
  return out;
}

/// `"` and `\` escaped, for text written inside a double-quoted YAML scalar.
String yamlEscape(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// Every file of the new app, relative to `apps/<id>/`, rendered from the
/// template at [templateDir].
///
/// Dependency versions come from the catalog (`pubspec_dependencies.yaml`
/// under [root], when given): the template carries none, so `dependency_sync
/// --check` holds the new app from its first commit.
Map<String, String> renderAppFiles(
  NewAppPlan plan, {
  required String templateDir,
  required String? root,
}) {
  final request = plan.request;
  final environment = _rootEnvironment(root);
  final versions = _catalogVersions(root);

  final values = <String, Object?>{
    'id': plan.id,
    'name': request.name,
    'pubspecName': plan.pubspecName,
    'sdk': environment.sdk,
    'flutter': environment.flutter,
    'v': {
      for (final name in _templateDependencies) name: versions[name] ?? '',
    },
    'platforms': [
      for (final name in request.platforms) {'name': name},
    ],
    'platformsCsv': request.platforms.join(','),
    'smokePlatform': plan.smokePlatform,
    'hasModules': plan.modules.isNotEmpty,
    'modulesCsv': plan.modules.map((m) => m.id).join(','),
    'modulesText': plan.modules.map((m) => m.id).join(', '),
    'modules': [
      for (final m in plan.modules) {'id': m.id, 'layers': m.layers.join(', ')},
    ],
    'corePackages': [
      for (final name in plan.corePackages) {'name': name},
    ],
    'coreWhy': plan.usesDatabase ? kCoreWhyDatabase : kCoreWhyPlain,
    'pinning': plan.anyPlatformCanPin,
    'pinReason': yamlEscape(kNewPinReason),
    // `directives_ordering` sorts by URI, so where the app's own package falls
    // depends on its id.
    'smokeImports': _sortedImports([
      '${plan.pubspecName}/app/app_profile.dart',
      '${plan.pubspecName}/di/injection.dart',
      'core_base_ui/core_base_ui.dart',
      'core_common/core_common.dart',
      'core_di/core_di.dart',
      'flutter_secure_storage/flutter_secure_storage.dart',
      'flutter_test/flutter_test.dart',
      'platform_app_shell/platform_app_shell.dart',
      'shared_preferences/shared_preferences.dart',
    ]),
    'profileTestImports': _sortedImports([
      '${plan.pubspecName}/app/app_profile.dart',
      'flutter_test/flutter_test.dart',
    ]),
    'capabilities': [
      for (final c in plan.capabilities)
        {
          'key': c.key,
          'provided': c.provided,
          'reason': yamlEscape(c.reason ?? ''),
        },
    ],
  };

  final out = <String, String>{};
  final dir = Directory(templateDir);
  if (!dir.existsSync()) {
    throw FileSystemException(
      'the app template is not at $templateDir — run `new` from the '
      'repository root',
    );
  }
  final files = [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.mustache')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final relative = p.posix
        .joinAll(p.split(p.relative(file.path, from: templateDir)))
        .replaceFirst(RegExp(r'\.mustache$'), '');
    out[relative] = Template(
      file.readAsStringSync(),
      name: relative,
      htmlEscapeValues: false,
    ).renderString(values);
  }
  return out;
}

/// `import 'package:<uri>';` lines for [uris], in the order the
/// `directives_ordering` lint wants them.
List<Map<String, String>> _sortedImports(List<String> uris) => [
  for (final uri in uris.toList()..sort()) {'line': "import 'package:$uri';"},
];

/// The external packages the template names.
const List<String> _templateDependencies = [
  'injectable',
  'flutter_secure_storage',
  'shared_preferences',
  'flutter_lints',
  'build_runner',
  'injectable_generator',
];

/// Name -> quoted version, from the catalog; empty when there is none.
Map<String, String> _catalogVersions(String? root) {
  if (root == null) return const {};
  final file = File(p.join(root, 'pubspec_dependencies.yaml'));
  if (!file.existsSync()) return const {};
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return const {};
    final out = <String, String>{};
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final map = doc[section];
      if (map is! YamlMap) continue;
      for (final entry in map.entries) {
        if (entry.key is String && entry.value is String) {
          out[entry.key as String] = '"${entry.value}"';
        }
      }
    }
    return out;
  } on YamlException {
    return const {};
  }
}

/// The root `pubspec.yaml`'s `environment:`, which every workspace member
/// copies.
({String sdk, String flutter}) _rootEnvironment(String? root) {
  const fallback = (sdk: '>=3.13.3 <4.0.0', flutter: '>=3.47.4');
  if (root == null) return fallback;
  try {
    final doc = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
    final env = doc is YamlMap ? doc['environment'] : null;
    if (env is YamlMap && env['sdk'] is String && env['flutter'] is String) {
      return (sdk: env['sdk'] as String, flutter: env['flutter'] as String);
    }
  } on Object {
    // Falls back below.
  }
  return fallback;
}

/// The lines `new` prints once the app is written and verified: what to run
/// next, and the one thing it deliberately did not do.
List<String> nextSteps(NewAppPlan plan) {
  final request = plan.request;
  return [
    'Created apps/${plan.id} (${request.name}) — ${request.platforms.join(', ')}'
        '${plan.modules.isEmpty ? '' : '; modules ${plan.modules.map((m) => m.id).join(', ')}'}.',
    'Capabilities, derived from what those modules register: '
        '${plan.capabilities.where((c) => c.provided).length} provided, '
        '${plan.capabilities.where((c) => !c.provided).length} absent. '
        '`dart tools/composer/composer.dart describe --app ${plan.id}` prints '
        'the report; apps/${plan.id}/app_manifest.yaml is where to change it.',
    '',
    'Next, from the repository root:',
    '  flutter pub get',
    '  dart run build_runner build --workspace',
    '  cd apps/${plan.id} && flutter test test/di_smoke_test.dart',
    '',
    'composer does NOT run `flutter create` — the native runners are the '
        'Flutter tool\'s to write. When you want them, run, once:',
    '  cd apps/${plan.id} && flutter create --platforms=${request.platforms.join(',')} '
        '--org com.example --project-name ${plan.pubspecName} .',
    'then declare each platform `runner: committed` in the manifest and run '
        '`dart tools/composer/composer.dart sync --app ${plan.id}`.',
    if (plan.usesDatabase)
      'This app links core_database: copy the path_provider and database '
          'doubles from apps/mobile/test/di_smoke_test.dart into its smoke test.',
  ];
}
