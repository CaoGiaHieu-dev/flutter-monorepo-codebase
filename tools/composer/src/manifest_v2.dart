import 'dart:convert';

import 'package:yaml/yaml.dart';

/// The declaration half of `app_manifest.yaml` (manifest v2): what an app *is*
/// and where it runs — identity, flavors and the pinning decision they carry,
/// environment keys, platforms, capabilities.
///
/// The composition half (`di_groups`, `modules`, `extra_dependencies`) stays
/// in `composer.dart`. This file holds two things:
///
///  1. [kManifestKeys], the **parse table** — the only description of the
///     schema. `composer describe --catalog` prints it, so there is no
///     hand-written key reference to rot, and a tools test fails when a key
///     names a consumer that does not read it (the `app.kind` bug class: a key
///     nothing read).
///  2. [parseDeclaration], which reads the table's keys into typed fields with
///     the same `<file>: <key>: <problem>` errors the rest of composer uses.
///
/// Nothing here imports Flutter or `platform_kernel`: composer runs before
/// code generation, so the enums below are *spelled* here and a tools test
/// (`app_sync_test.dart`) keeps them equal to the kernel's.

/// The `.env` file each flavor reads, by the repository's convention.
const Map<String, String> kEnvFiles = {
  'dev': 'env.dev',
  'staging': 'env.stg',
  'prod': 'env.prod',
};

/// `Flavor` in `platform_kernel`, in declaration order.
const List<String> kFlavorNames = ['dev', 'staging', 'prod'];

/// `AppPlatform` in `platform_kernel`, in declaration order.
const List<String> kPlatformNames = [
  'android',
  'ios',
  'web',
  'windows',
  'macos',
  'linux',
];

/// `AppPlatform.canPinTls` in `platform_kernel`: `http_security_pinning` has a
/// native side on these only.
const Set<String> kPinnablePlatforms = {'android', 'ios'};

/// `RunnerKind` in `platform_kernel`.
const List<String> kRunnerKinds = ['committed', 'scaffold'];

/// `SplashMode` in `platform_kernel`.
const List<String> kSplashModes = ['dart', 'native'];

/// `OrientationPolicy` in `platform_kernel`, spelled snake_case as the
/// manifest writes it (`phones_portrait` is `OrientationPolicy.phonesPortrait`).
const List<String> kOrientationPolicies = [
  'phones_portrait',
  'free',
  'portrait',
  'landscape',
];

/// The orientation policy of a platform that says nothing.
const String kDefaultOrientation = 'phones_portrait';

/// `AppPlatform.isDesktop` in `platform_kernel`: the platforms with a
/// resizable window, the only ones that can declare a `window`.
const Set<String> kDesktopPlatforms = {'windows', 'macos', 'linux'};

/// `phones_portrait` as the kernel's `OrientationPolicy` constant.
String orientationConstant(String policy) => switch (policy) {
  'phones_portrait' => 'phonesPortrait',
  _ => policy,
};

/// What `composer new` writes as the reason of an `absent` capability: the
/// state of the app, not yet a decision of its author. The report lists every
/// reason that starts with it under "Decisions to revisit", so absence stays
/// something somebody chose (RULE-81) rather than something nobody noticed.
const String kNotComposedPrefix = 'not composed:';

/// The `dev` flavor's pinning decision when the manifest says nothing: the dev
/// flavor exists to talk to local servers with self-signed certificates.
const String kDevPinReason =
    'development flavor: local servers use self-signed certificates';

/// One key of the manifest and what reads it.
class KeySpec {
  const KeySpec({
    required this.key,
    required this.type,
    required this.defaultValue,
    required this.validation,
    required this.consumer,
    required this.reads,
    required this.replaces,
    this.reportOnly = false,
  });

  /// The dotted key path, `<p>` / `<f>` / `<KEY>` / `<id>` standing for a map
  /// key.
  final String key;

  /// Type and allowed values.
  final String type;

  /// What the key means when left out, as the report states it.
  final String defaultValue;

  /// What is refused.
  final String validation;

  /// Repo-relative path of the file that reads the key.
  final String consumer;

  /// The expression in [consumer] that *uses* the key's value — a member
  /// access or a call (`facts.name`, `platformFacts.splash`), never a bare
  /// field name, which a declaration also contains and which therefore proves
  /// nothing. A tools test requires the file to contain it, and requires it to
  /// name a member (`.` or `(`).
  final String reads;

  /// What this replaces, or `none`.
  final String replaces;

  /// True when only composer reads the key (a check and the report); no
  /// runtime code does. The key is still carried in the generated facts, for
  /// tests and `describe`, and the catalog says so instead of "read by".
  final bool reportOnly;
}

/// The parse table: every key of the declaration half, with its consumer.
///
/// A key exists only together with its consumer. Where a platform's
/// `push`, `deep_links`, `orientation` or `window` is left out, the generated
/// facts carry the derived default of each (`facts_emit.dart`), so a generated
/// app never depends on a Dart default.
const List<KeySpec> kManifestKeys = [
  KeySpec(
    key: 'app.id',
    type: 'package-name string',
    defaultValue: 'required',
    validation: 'unique across apps',
    consumer:
        'platform/shell/app_shell/lib/src/composition/composition_check.dart',
    reads: 'facts.id',
    replaces: 'the same key in manifest v1',
  ),
  KeySpec(
    key: 'app.name',
    type: 'non-empty string',
    defaultValue:
        'required — what the app is called: the window and task-switcher '
        'title unless the build defines APP_NAME, which overrides it per '
        'flavor',
    validation: 'non-empty',
    consumer: 'platform/shell/app_shell/lib/src/app_material_wrapper.dart',
    reads: 'facts.name',
    replaces:
        'the APP_NAME env key as the only name: it is now the per-flavor '
        'override of this one (`Codebase (DEV)`), so a flavor still tells '
        'itself apart',
  ),
  KeySpec(
    key: 'app.entrypoint',
    type: 'path',
    defaultValue: 'lib/main.dart',
    validation: 'non-empty string',
    consumer: 'tools/composer/src/report.dart',
    reads: 'decl.entrypoint',
    replaces: 'the dead key of manifest v1 (nothing read it)',
  ),
  KeySpec(
    key: 'flavors.<f>',
    type: 'f is dev | staging | prod; value empty or { ssl_pinning }',
    defaultValue: 'required, at least one',
    validation: 'closed vocabulary (Flavor)',
    consumer: 'platform/foundation/kernel/lib/src/profile/app_profile.dart',
    reads: 'facts.flavors',
    replaces: "the ['dev','staging','prod'] literals of the smoke tests",
  ),
  KeySpec(
    key: 'flavors.<f>.ssl_pinning',
    type: '{ pins: [base64, ...] } or { disabled: "reason" }',
    defaultValue:
        'dev: disabled, "$kDevPinReason"; staging and prod: no default, '
        'must be decided whenever a declared platform can pin TLS',
    validation:
        'pins: at least 2 (leaf and backup), each the base64 of 32 bytes; '
        'a reason is non-empty and not TODO/TBD; refused when no declared '
        'platform can pin',
    consumer: 'platform/foundation/common/lib/src/config/app_initializer.dart',
    reads: 'facts.sslPinning',
    replaces: 'NetworkConfigImpl.sslPinningHashes = const []',
  ),
  KeySpec(
    key: 'env.<KEY>',
    type: '{ required_in: [flavor, ...], native_only: bool }',
    defaultValue: '{}',
    validation:
        'KEY is UPPER_SNAKE; required_in names declared flavors; a '
        'native_only key is never emitted to Dart and never checked at boot',
    consumer: 'platform/foundation/kernel/lib/src/profile/app_profile.dart',
    reads: 'facts.env',
    replaces: 'env_constants.dart: an empty BASE_URL was accepted silently',
  ),
  KeySpec(
    key: 'platforms.<p>',
    type: 'p is android | ios | web | windows | macos | linux',
    defaultValue: 'required, at least one',
    validation: 'closed vocabulary (AppPlatform)',
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart',
    reads: 'facts.platformFor(',
    replaces: 'nothing declared the platforms an app runs on',
  ),
  KeySpec(
    key: 'platforms.<p>.runner',
    type: 'committed | scaffold',
    defaultValue: 'required',
    validation:
        'committed: apps/<id>/<p>/ exists; scaffold: it does not '
        '(the report prints the flutter create line)',
    consumer: 'tools/composer/src/checks.dart',
    reads: 'platform.runner',
    replaces: 'a runner folder was the only sign of a platform',
    reportOnly: true,
  ),
  KeySpec(
    key: 'platforms.<p>.splash',
    type: 'dart | native',
    defaultValue:
        'ios: native; else dart when capability splash is provided, '
        'else native',
    validation: 'dart needs capability splash provided',
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart',
    reads: 'platformFacts.splash',
    replaces: 'usesDartSplash = kIsWeb || !Platform.isIOS',
  ),
  KeySpec(
    key: 'platforms.<p>.push',
    type: 'bool',
    defaultValue:
        'true when core_notifications is composed and supports the platform '
        '(web: false, no service worker is shipped), else false',
    validation: 'true needs core_notifications composed and supporting <p>',
    consumer:
        'platform/infra/notifications/lib/src/push_notification_service.dart',
    reads: '_platform.push',
    replaces: 'push was initialised on every platform the package compiled for',
  ),
  KeySpec(
    key: 'platforms.<p>.deep_links',
    type: 'bool',
    defaultValue: 'true',
    validation: 'none',
    consumer:
        'platform/shell/app_shell/lib/src/provider/deeplink_provider.dart',
    reads: '_platform.deepLinks',
    replaces: 'deep links were subscribed on every platform',
  ),
  KeySpec(
    key: 'platforms.<p>.orientation',
    type: 'phones_portrait | free | portrait | landscape',
    defaultValue:
        'phones_portrait: displays under the phone threshold are '
        'locked to portrait, larger ones rotate freely',
    validation: 'closed vocabulary (OrientationPolicy)',
    consumer: 'platform/foundation/common/lib/src/config/app_initializer.dart',
    reads: 'facts?.orientation',
    replaces: 'the portrait lock hardcoded in AppInitializer',
  ),
  KeySpec(
    key: 'platforms.<p>.window',
    type: '{ initial: [width, height], min: [width, height] }',
    defaultValue: 'none: the shell does not touch the window',
    validation:
        'desktop platforms only (windows, macos, linux); every side '
        'positive; min no larger than initial; the app must pass a '
        'ShellHooks.configureWindow hook (boot problem P05 otherwise)',
    consumer: 'platform/shell/app_shell/lib/src/bootstrap.dart',
    reads: 'platformFacts.window',
    replaces: 'no seam at all: a desktop window opened at the OS default',
  ),
  KeySpec(
    key: 'capabilities.<id>',
    type: 'provided, or { state: absent, reason: "..." }',
    defaultValue: 'required for every optional contract in the catalog',
    validation:
        'each id declared once; a bundle id (session) expands to its '
        'members, which share one state; a reason is non-empty and not '
        'TODO/TBD',
    consumer:
        'platform/shell/app_shell/lib/src/composition/composition_check.dart',
    reads: 'facts.capabilities',
    replaces: 'eleven unchecked lookups in each smoke test',
  ),
  KeySpec(
    key: 'di_groups[].why',
    type: 'string',
    defaultValue: 'none',
    validation: 'none',
    consumer: 'tools/composer/src/report.dart',
    reads: 'group.why',
    replaces: 'prose comments in the manifest',
  ),
];

/// The `ssl_pinning` decision of one flavor, as written.
class SslDecl {
  const SslDecl.pins(List<String> this.pins) : disabledReason = null;
  const SslDecl.disabled(String this.disabledReason) : pins = null;

  /// The pinned hashes, base64 SPKI SHA-256, leaf first.
  final List<String>? pins;

  /// Why the flavor does not pin.
  final String? disabledReason;

  bool get isPinned => pins != null;
}

/// One `env` key.
class EnvDecl {
  const EnvDecl(this.key, this.requiredIn, {required this.nativeOnly});

  final String key;

  /// Flavor names, in canonical order.
  final List<String> requiredIn;

  /// Read by Gradle / Xcode only: no Dart reader, never emitted.
  final bool nativeOnly;
}

/// A width x height as the manifest writes it, `[width, height]`.
class SizeDecl {
  const SizeDecl(this.width, this.height);

  final num width;
  final num height;

  /// Whether this is no larger than [other] on both sides.
  bool fitsWithin(SizeDecl other) =>
      width <= other.width && height <= other.height;
}

/// The `window` of one desktop platform.
class WindowDecl {
  const WindowDecl(this.initial, this.min);

  final SizeDecl initial;

  /// The smallest the window may be resized to, or null for no floor.
  final SizeDecl? min;
}

/// One declared platform.
class PlatformDecl {
  const PlatformDecl(
    this.name,
    this.runner,
    this.splash, {
    this.push,
    this.deepLinks,
    this.orientation,
    this.window,
  });

  final String name;
  final String runner;

  /// `dart` / `native`, or null when the manifest leaves it to the default.
  final String? splash;

  /// Whether push is on, or null when the manifest leaves it to the default.
  final bool? push;

  /// Whether deep links are on, or null when the manifest leaves it to the
  /// default.
  final bool? deepLinks;

  /// One of [kOrientationPolicies], or null when the manifest leaves it to the
  /// default.
  final String? orientation;

  /// The declared desktop window, or null.
  final WindowDecl? window;
}

/// One `capabilities` entry as written (a bundle or a single contract).
class CapabilityDecl {
  const CapabilityDecl.provided() : provided = true, reason = null;
  const CapabilityDecl.absent(String this.reason) : provided = false;

  final bool provided;

  /// Why the app has none; null when [provided].
  final String? reason;
}

/// What the declaration half of a manifest says.
class AppDeclaration {
  AppDeclaration({
    required this.name,
    required this.entrypoint,
    required this.flavors,
    required this.env,
    required this.platforms,
    required this.capabilities,
  });

  final String name;

  /// `lib/main.dart` unless the manifest says otherwise.
  final String entrypoint;

  /// Flavor name -> its `ssl_pinning` decision, or null when none is written.
  /// In canonical order, whatever order the manifest used.
  final Map<String, SslDecl?> flavors;
  final List<EnvDecl> env;

  /// In canonical `AppPlatform` order.
  final List<PlatformDecl> platforms;

  /// Key (a bundle id or a contract id) -> declaration, in manifest order.
  final Map<String, CapabilityDecl> capabilities;

  /// Whether any declared platform can enforce TLS pinning.
  bool get anyPlatformCanPin =>
      platforms.any((p) => kPinnablePlatforms.contains(p.name));

  PlatformDecl? platform(String name) {
    for (final p in platforms) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// A reason a person wrote that says nothing: empty, `TODO`, `TBD`.
///
/// Absence is a decision; a placeholder is the lack of one.
bool isEmptyReason(String reason) {
  final text = reason.trim();
  if (text.isEmpty) return true;
  return RegExp(r'^(todo|tbd)(\W.*)?$', caseSensitive: false).hasMatch(text);
}

final _envKey = RegExp(r'^[A-Z][A-Z0-9_]*$');

/// The keys a `platforms.<p>` map may hold.
const _platformKeys = [
  'runner',
  'splash',
  'push',
  'deep_links',
  'orientation',
  'window',
];

/// A boolean switch (`push`, `deep_links`) of platform [map], or null when it
/// is left out. A value that is not a boolean is reported to [fail].
bool? _parseSwitch(
  YamlMap map,
  String key,
  String path,
  void Function(String key, String problem) fail,
) {
  final value = map[key];
  if (value == null) return null;
  if (value is bool) return value;
  fail('$path.$key', 'expected true or false, got ${describeValue(value)}');
  return null;
}

/// `{ initial: [w, h], min: [w, h] }`, or null after reporting why not.
WindowDecl? _parseWindow(
  Object? raw,
  String path,
  void Function(String key, String problem) fail,
) {
  if (raw is! YamlMap) {
    fail(
      path,
      'expected `{ initial: [width, height], min: [width, height] }`, got '
      '${describeValue(raw)}',
    );
    return null;
  }
  var ok = true;
  for (final key in raw.keys) {
    if (key != 'initial' && key != 'min') {
      fail('$path.$key', 'unknown key — expected initial, min');
      ok = false;
    }
  }
  SizeDecl? size(String key, {required bool required}) {
    final value = raw[key];
    if (value == null) {
      if (required) {
        fail(
          '$path.$key',
          'expected `[width, height]` in logical pixels, got nothing',
        );
        ok = false;
      }
      return null;
    }
    if (value is YamlList &&
        value.length == 2 &&
        value[0] is num &&
        value[1] is num &&
        (value[0] as num) > 0 &&
        (value[1] as num) > 0) {
      return SizeDecl(value[0] as num, value[1] as num);
    }
    fail(
      '$path.$key',
      'expected `[width, height]` in logical pixels, two positive numbers, '
          'got ${describeValue(value)}',
    );
    ok = false;
    return null;
  }

  final initial = size('initial', required: true);
  final min = size('min', required: false);
  if (initial != null && min != null && !min.fitsWithin(initial)) {
    fail(
      '$path.min',
      'the minimum size must not exceed the initial size: '
          '${min.width} x ${min.height} does not fit within '
          '${initial.width} x ${initial.height}',
    );
    ok = false;
  }
  if (!ok || initial == null) return null;
  return WindowDecl(initial, min);
}

/// `a string (`x`)`, `a list`, `nothing` — for "expected X, got Y".
String describeValue(Object? value) => switch (value) {
  null => 'nothing',
  String() => 'a string (`$value`)',
  bool() => 'a boolean (`$value`)',
  num() => 'a number (`$value`)',
  YamlList() || List() => 'a list',
  YamlMap() || Map() => 'a map',
  _ => 'a ${value.runtimeType}',
};

/// Whether [pin] is the base64 of 32 bytes — a SHA-256 digest.
bool isSha256Base64(String pin) {
  try {
    return base64.decode(pin).length == 32 &&
        base64.encode(base64.decode(pin)) == pin;
  } on FormatException {
    return false;
  }
}

/// Reads the declaration half of [doc], adding one `<key>: <problem>` line to
/// [bad] per defect. Returns null when there is any.
AppDeclaration? parseDeclaration(
  YamlMap doc,
  void Function(String key, String problem) bad,
) {
  var ok = true;
  void fail(String key, String problem) {
    ok = false;
    bad(key, problem);
  }

  // -- app ------------------------------------------------------------------
  String? name;
  var entrypoint = 'lib/main.dart';
  final app = doc['app'];
  if (app is YamlMap) {
    if (app.containsKey('kind')) {
      fail(
        'app.kind',
        'removed — it had no consumer; delete the line',
      );
    }
    final rawName = app['name'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      name = rawName;
    } else {
      fail(
        'app.name',
        'expected a non-empty string, got ${describeValue(rawName)} — '
            'add `name: <display name>` under `app:`',
      );
    }
    final rawEntry = app['entrypoint'];
    if (rawEntry != null) {
      if (rawEntry is String && rawEntry.trim().isNotEmpty) {
        entrypoint = rawEntry;
      } else {
        fail(
          'app.entrypoint',
          'expected a non-empty string, got ${describeValue(rawEntry)}',
        );
      }
    }
  }

  // -- flavors ----------------------------------------------------------------
  final flavors = <String, SslDecl?>{};
  final rawFlavors = doc['flavors'];
  if (rawFlavors is! YamlMap || rawFlavors.isEmpty) {
    fail(
      'flavors',
      'expected a map naming at least one flavor, got '
          '${rawFlavors is YamlMap ? 'an empty map' : describeValue(rawFlavors)}'
          ' — add:\n    flavors:\n      dev:\n      staging:\n      prod:',
    );
  } else {
    final written = <String, SslDecl?>{};
    for (final entry in rawFlavors.entries) {
      final flavor = entry.key;
      if (flavor is! String || !kFlavorNames.contains(flavor)) {
        fail(
          'flavors.$flavor',
          'expected one of ${kFlavorNames.join(', ')}, got '
              '${describeValue(flavor)}',
        );
        continue;
      }
      final value = entry.value;
      if (value == null) {
        written[flavor] = null;
        continue;
      }
      if (value is! YamlMap) {
        fail(
          'flavors.$flavor',
          'expected nothing or `{ ssl_pinning: ... }`, got '
              '${describeValue(value)}',
        );
        continue;
      }
      for (final key in value.keys) {
        if (key != 'ssl_pinning') {
          fail(
            'flavors.$flavor.$key',
            'unknown key — expected ssl_pinning',
          );
        }
      }
      if (!value.containsKey('ssl_pinning')) {
        written[flavor] = null;
        continue;
      }
      final decl = _parsePinning(
        value['ssl_pinning'],
        'flavors.$flavor.ssl_pinning',
        fail,
      );
      if (decl != null) written[flavor] = decl;
    }
    for (final flavor in kFlavorNames) {
      if (written.containsKey(flavor)) flavors[flavor] = written[flavor];
    }
  }

  // -- env --------------------------------------------------------------------
  final env = <EnvDecl>[];
  final rawEnv = doc['env'];
  if (rawEnv != null) {
    if (rawEnv is! YamlMap) {
      fail(
        'env',
        'expected a map of KEY -> `{ required_in: [...] }`, got ${describeValue(rawEnv)}',
      );
    } else {
      for (final entry in rawEnv.entries) {
        final key = entry.key;
        final path = 'env.$key';
        if (key is! String || !_envKey.hasMatch(key)) {
          fail(path, 'expected an UPPER_SNAKE key, got ${describeValue(key)}');
          continue;
        }
        final value = entry.value;
        if (value != null && value is! YamlMap) {
          fail(
            path,
            'expected nothing or `{ required_in: [...], native_only: bool }`, '
            'got ${describeValue(value)}',
          );
          continue;
        }
        final map = value as YamlMap?;
        for (final k in map?.keys ?? const <Object?>[]) {
          if (k != 'required_in' && k != 'native_only') {
            fail('$path.$k', 'unknown key — expected required_in, native_only');
          }
        }
        final rawRequired = map?['required_in'];
        final required = <String>[];
        if (rawRequired != null) {
          if (rawRequired is! YamlList) {
            fail(
              '$path.required_in',
              'expected a list of flavors, got ${describeValue(rawRequired)}',
            );
          } else {
            for (var i = 0; i < rawRequired.length; i++) {
              final f = rawRequired[i];
              if (f is String && kFlavorNames.contains(f)) {
                if (!required.contains(f)) required.add(f);
              } else {
                fail(
                  '$path.required_in[$i]',
                  'expected one of ${kFlavorNames.join(', ')}, got '
                      '${describeValue(f)}',
                );
              }
            }
          }
        }
        final rawNative = map?['native_only'];
        if (rawNative != null && rawNative is! bool) {
          fail(
            '$path.native_only',
            'expected true or false, got ${describeValue(rawNative)}',
          );
        }
        final native = rawNative == true;
        if (native && required.isNotEmpty) {
          fail(
            path,
            'native_only keys are read by Gradle / Xcode and never checked at '
            'boot, so `required_in` has no effect — drop one of the two',
          );
        }
        required.sort(
          (a, b) => kFlavorNames.indexOf(a).compareTo(kFlavorNames.indexOf(b)),
        );
        env.add(EnvDecl(key, required, nativeOnly: native));
      }
    }
  }

  // -- platforms ----------------------------------------------------------------
  final platforms = <PlatformDecl>[];
  final rawPlatforms = doc['platforms'];
  if (rawPlatforms is! YamlMap || rawPlatforms.isEmpty) {
    fail(
      'platforms',
      'expected a map naming at least one platform, got '
          '${rawPlatforms is YamlMap ? 'an empty map' : describeValue(rawPlatforms)}'
          ' — an app that does not say where it runs is the problem this '
          'section solves; add, e.g.:\n    platforms:\n'
          '      android: { runner: committed }\n'
          '      ios:     { runner: committed }',
    );
  } else {
    final written = <String, PlatformDecl>{};
    for (final entry in rawPlatforms.entries) {
      final platform = entry.key;
      final path = 'platforms.$platform';
      if (platform is! String || !kPlatformNames.contains(platform)) {
        fail(
          path,
          'expected one of ${kPlatformNames.join(', ')}, got '
          '${describeValue(platform)}',
        );
        continue;
      }
      final value = entry.value;
      if (value is! YamlMap) {
        fail(
          path,
          'expected `{ runner: committed | scaffold }`, got '
          '${describeValue(value)}',
        );
        continue;
      }
      for (final key in value.keys) {
        if (!_platformKeys.contains(key)) {
          fail(
            '$path.$key',
            'unknown key — expected ${_platformKeys.join(', ')}',
          );
        }
      }
      final runner = value['runner'];
      if (runner is! String || !kRunnerKinds.contains(runner)) {
        fail(
          '$path.runner',
          'expected one of ${kRunnerKinds.join(', ')}, got '
              '${describeValue(runner)} — `committed` when apps/<id>/$platform/ '
              'is in the repository, `scaffold` when the owner runs '
              '`flutter create` for it',
        );
        continue;
      }
      final splash = value['splash'];
      if (splash != null &&
          (splash is! String || !kSplashModes.contains(splash))) {
        fail(
          '$path.splash',
          'expected one of ${kSplashModes.join(', ')}, got '
              '${describeValue(splash)}',
        );
        continue;
      }
      final push = _parseSwitch(value, 'push', path, fail);
      final deepLinks = _parseSwitch(value, 'deep_links', path, fail);
      final orientation = value['orientation'];
      if (orientation != null &&
          (orientation is! String ||
              !kOrientationPolicies.contains(orientation))) {
        fail(
          '$path.orientation',
          'expected one of ${kOrientationPolicies.join(', ')}, got '
              '${describeValue(orientation)}',
        );
        continue;
      }
      final window = value.containsKey('window')
          ? _parseWindow(value['window'], '$path.window', fail)
          : null;
      if (value.containsKey('window') && window == null) continue;
      written[platform] = PlatformDecl(
        platform,
        runner,
        splash as String?,
        push: push,
        deepLinks: deepLinks,
        orientation: orientation as String?,
        window: window,
      );
    }
    for (final platform in kPlatformNames) {
      final decl = written[platform];
      if (decl != null) platforms.add(decl);
    }
  }

  // -- capabilities ---------------------------------------------------------------
  final capabilities = <String, CapabilityDecl>{};
  final rawCaps = doc['capabilities'];
  if (rawCaps is! YamlMap) {
    fail(
      'capabilities',
      'expected a map of contract id -> `provided` or '
          '`{ state: absent, reason: "..." }`, got ${describeValue(rawCaps)} — '
          '`composer describe --catalog` lists the ids',
    );
  } else {
    for (final entry in rawCaps.entries) {
      final id = entry.key;
      final path = 'capabilities.$id';
      if (id is! String) {
        fail(path, 'expected a contract id, got ${describeValue(id)}');
        continue;
      }
      final value = entry.value;
      if (value == 'provided') {
        capabilities[id] = const CapabilityDecl.provided();
      } else if (value is YamlMap) {
        for (final key in value.keys) {
          if (key != 'state' && key != 'reason') {
            fail('$path.$key', 'unknown key — expected state, reason');
          }
        }
        if (value['state'] != 'absent') {
          fail(
            '$path.state',
            'expected `absent`, got ${describeValue(value['state'])} — a '
                'provided contract is written `$id: provided`',
          );
          continue;
        }
        final reason = value['reason'];
        if (reason is! String) {
          fail(
            '$path.reason',
            'expected a string saying why the app has none, got '
                '${describeValue(reason)}',
          );
          continue;
        }
        capabilities[id] = CapabilityDecl.absent(reason);
      } else {
        fail(
          path,
          'expected `provided` or `{ state: absent, reason: "..." }`, got '
          '${describeValue(value)}',
        );
      }
    }
  }

  if (!ok || name == null) return null;
  return AppDeclaration(
    name: name,
    entrypoint: entrypoint,
    flavors: flavors,
    env: env,
    platforms: platforms,
    capabilities: capabilities,
  );
}

SslDecl? _parsePinning(
  Object? raw,
  String path,
  void Function(String key, String problem) fail,
) {
  if (raw is! YamlMap) {
    fail(
      path,
      'expected `{ pins: ["<leaf>", "<backup>"] }` or '
      '`{ disabled: "<reason>" }`, got ${describeValue(raw)}',
    );
    return null;
  }
  for (final key in raw.keys) {
    if (key != 'pins' && key != 'disabled') {
      fail('$path.$key', 'unknown key — expected pins, disabled');
    }
  }
  final pins = raw['pins'];
  final disabled = raw['disabled'];
  if ((pins == null) == (disabled == null)) {
    fail(
      path,
      'decide one of `pins: ["<leaf spki sha256 base64>", '
      '"<backup spki sha256 base64>"]` or `disabled: "<reason>"`',
    );
    return null;
  }
  if (disabled != null) {
    if (disabled is! String) {
      fail(
        '$path.disabled',
        'expected a string saying why, got ${describeValue(disabled)}',
      );
      return null;
    }
    return SslDecl.disabled(disabled);
  }
  if (pins is! YamlList) {
    fail('$path.pins', 'expected a list of hashes, got ${describeValue(pins)}');
    return null;
  }
  final hashes = <String>[];
  for (var i = 0; i < pins.length; i++) {
    final pin = pins[i];
    if (pin is String && isSha256Base64(pin)) {
      hashes.add(pin);
    } else {
      fail(
        '$path.pins[$i]',
        'expected the base64 of a 32-byte SPKI SHA-256 hash, got '
            '${describeValue(pin)}',
      );
    }
  }
  if (hashes.length != pins.length) return null;
  if (hashes.length < 2) {
    fail(
      '$path.pins',
      'pin at least two keys — the leaf and a backup — so a certificate '
          'rotation cannot lock every installed app out of the API',
    );
    return null;
  }
  if (hashes.toSet().length != hashes.length) {
    fail(
      '$path.pins',
      'the backup must differ from the leaf: a hash is listed twice',
    );
    return null;
  }
  return SslDecl.pins(hashes);
}
