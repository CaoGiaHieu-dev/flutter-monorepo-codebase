import 'catalog.dart';
import 'manifest_v2.dart';
import 'native_flavors.dart';
import 'package_facts.dart';
import 'profile_summary.dart';
import 'provisions.dart';

/// One `di_groups` entry, resolved to the packages it composes.
class ViewGroup {
  const ViewGroup({
    required this.name,
    required this.phase,
    required this.packages,
    required this.why,
  });

  final String name;
  final String phase;

  /// Package names — the group's own, then the ones its `from_modules` layer
  /// collects.
  final List<String> packages;

  /// The manifest's `why:`, or null.
  final String? why;
}

/// One `modules` entry.
class ViewModule {
  const ViewModule(this.id, this.layers);

  final String id;
  final List<String> layers;
}

/// Everything the generators know about one app, gathered once.
///
/// [facts_emit] and [report] render from this and from nothing else, so the
/// facts the shell reads at boot and the report a person reads cannot disagree.
class AppView {
  const AppView({
    required this.id,
    required this.dir,
    required this.pubspecName,
    required this.declaration,
    required this.groups,
    required this.modules,
    required this.composed,
    required this.packageFacts,
    required this.catalog,
    this.provisions = const ProvisionIndex.empty(),
    this.native = const NativeFlavors.none(),
    this.profile = const ProfileOverrides.unknown(),
    this.shippedLanguages = const [],
  });

  final String id;

  /// Repo-relative app directory (`apps/mobile`).
  final String dir;

  /// The app package's name (`mobile_app`).
  final String pubspecName;

  final AppDeclaration declaration;
  final List<ViewGroup> groups;
  final List<ViewModule> modules;

  /// Every package the app composes: DI groups and `extra_dependencies`.
  final Set<String> composed;

  /// Facts of every package in the workspace closure of [composed], by name.
  final Map<String, PackageFacts> packageFacts;

  final ShellCatalog catalog;

  /// What every workspace package registers, from the static scan.
  final ProvisionIndex provisions;

  /// The flavors the committed Android and iOS runners declare, read as text.
  final NativeFlavors native;

  /// The profile sections the app's own `lib/app/app_profile.dart` sets.
  final ProfileOverrides profile;

  /// The language codes the template ships (the ARB files of `core_base_ui`),
  /// empty when unknown.
  final List<String> shippedLanguages;

  /// The packages whose registrations are part of this app's graph: the ones it
  /// composes, and the app's own `lib/`.
  Set<String> get graphPackages => {...composed, pubspecName};

  /// The registrations of [type] in this app's graph.
  List<Provision> providersOf(String type) =>
      provisions.of(type, graphPackages);

  String get manifestPath => '$dir/app_manifest.yaml';

  /// Whether `core_notifications` is composed — what turns push on.
  bool get composesNotifications => composed.contains(kNotificationsPackage);

  /// The state the manifest declares for catalog row [id], bundles expanded.
  CapabilityDecl? capability(String id) {
    final direct = declaration.capabilities[id];
    if (direct != null) return direct;
    for (final entry in catalog.optional) {
      if (entry.id == id && entry.bundle != null) {
        return declaration.capabilities[entry.bundle!];
      }
    }
    return null;
  }

  bool get splashProvided => capability('splash')?.provided ?? false;
}

/// The package whose composition decides `push`.
const String kNotificationsPackage = 'core_notifications';

/// Where a derived value came from — printed next to it in the generated
/// facts and in the report.
class Sourced<T> {
  const Sourced(this.value, this.source);

  final T value;

  /// `manifest`, `default`, `default: <why>` or `derived: <why>`.
  final String source;
}

/// Everything one platform enables, with every field explicit and where each
/// came from.
class DerivedPlatform {
  const DerivedPlatform({
    required this.name,
    required this.runner,
    required this.splash,
    required this.orientation,
    required this.deepLinks,
    required this.push,
    this.window,
  });

  final String name;
  final Sourced<String> runner;
  final Sourced<String> splash;

  /// The kernel's `OrientationPolicy` constant (`phonesPortrait`).
  final Sourced<String> orientation;
  final Sourced<bool> deepLinks;
  final Sourced<bool> push;

  /// The declared desktop window; null when the manifest declares none.
  final Sourced<WindowDecl>? window;
}

/// The effective facts of every declared platform.
///
/// The one derivation table (`composer describe --catalog` prints it):
///
/// - `splash`: iOS keeps its native splash for the whole boot; elsewhere the
///   Dart splash when capability `splash` is provided, else the native one;
/// - `push`: on when `core_notifications` is composed and supports the
///   platform — but never on the web, where no service worker is shipped;
/// - `deep_links`: on everywhere;
/// - `orientation`: phone-sized displays locked to portrait;
/// - `window`: none — the shell does not touch the window;
///
/// and each of them is what the manifest says when it says anything
/// (`platforms.<p>.push`, `.deep_links`, `.orientation`, `.window`).
///
/// `PlatformFacts.today()` in the kernel holds the same defaults for a
/// hand-built object; `app_sync_test.dart` compares the two.
List<DerivedPlatform> derivePlatforms(AppView view) {
  final out = <DerivedPlatform>[];
  final notifications = view.packageFacts[kNotificationsPackage];
  for (final platform in view.declaration.platforms) {
    final name = platform.name;

    final Sourced<String> splash;
    if (platform.splash != null) {
      splash = Sourced(platform.splash!, 'manifest');
    } else if (name == 'ios') {
      splash = const Sourced(
        'native',
        'default: iOS keeps its native splash for the whole boot',
      );
    } else if (view.splashProvided) {
      splash = const Sourced(
        'dart',
        'derived: capability `splash` is provided',
      );
    } else {
      splash = const Sourced(
        'native',
        'derived: capability `splash` is absent',
      );
    }

    final Sourced<bool> push;
    if (platform.push != null) {
      push = Sourced(platform.push!, 'manifest');
    } else if (!view.composesNotifications) {
      push = const Sourced(
        false,
        'derived: core_notifications is not composed',
      );
    } else if (name == 'web') {
      push = const Sourced(
        false,
        'derived: no service worker is shipped for web',
      );
    } else if (notifications != null && !notifications.supports(name)) {
      push = Sourced(
        false,
        'derived: core_notifications does not support $name',
      );
    } else {
      push = Sourced(
        true,
        'derived: core_notifications is composed and supports $name',
      );
    }

    out.add(
      DerivedPlatform(
        name: name,
        runner: Sourced(platform.runner, 'manifest'),
        splash: splash,
        orientation: platform.orientation == null
            ? const Sourced('phonesPortrait', 'default')
            : Sourced(orientationConstant(platform.orientation!), 'manifest'),
        deepLinks: platform.deepLinks == null
            ? const Sourced(true, 'default')
            : Sourced(platform.deepLinks!, 'manifest'),
        push: push,
        window: platform.window == null
            ? null
            : Sourced(platform.window!, 'manifest'),
      ),
    );
  }
  return out;
}

/// The pinning decision of each declared flavor, with where it came from, or
/// an empty map when no declared platform can pin TLS (nothing to decide).
Map<String, Sourced<SslDecl>> deriveSslDecisions(AppView view) {
  final decl = view.declaration;
  if (!decl.anyPlatformCanPin) return const {};
  final out = <String, Sourced<SslDecl>>{};
  for (final entry in decl.flavors.entries) {
    final written = entry.value;
    if (written != null) {
      out[entry.key] = Sourced(written, 'manifest');
    } else if (entry.key == 'dev') {
      out[entry.key] = const Sourced(
        SslDecl.disabled(kDevPinReason),
        'default',
      );
    }
    // staging / prod with no decision: refused by `checks.dart`.
  }
  return out;
}

// ---------------------------------------------------------------------------
// The `facts` region
// ---------------------------------------------------------------------------

/// The text between `// composer:managed:facts` and `// composer:end:facts` in
/// `apps/<id>/lib/app/app_profile.dart`.
///
/// **A fixed point of `dart format`** under the repository's
/// `analysis_options.yaml` (`trailing_commas: preserve`): every call is one
/// argument per line with a trailing comma, a long string is split into
/// adjacent literals, and the provenance of each entry sits on its own line
/// above it, never trailing — a trailing comment or a long one-line call is
/// what a local format pass would reflow, putting the file out of step with
/// `composer verify`. `composer_report_test.dart` runs the formatter over a
/// sample and requires no change.
String emitFacts(AppView view) {
  final decl = view.declaration;
  final b = StringBuffer();
  void line(int indent, String text) => b
    ..write('  ' * indent)
    ..writeln(text);
  void note(int indent, String text) => line(indent, '// $text');

  line(0, 'const AppFacts appFacts = AppFacts(');
  line(1, 'id: ${dartString(view.id)},');
  line(1, 'name: ${dartString(decl.name)},');
  line(
    1,
    'flavors: {${decl.flavors.keys.map((f) => 'Flavor.$f').join(', ')}},',
  );

  line(1, 'platforms: {');
  for (final platform in derivePlatforms(view)) {
    line(2, 'AppPlatform.${platform.name}: PlatformFacts(');
    note(3, platform.runner.source);
    line(3, 'runner: RunnerKind.${platform.runner.value},');
    note(3, platform.splash.source);
    line(3, 'splash: SplashMode.${platform.splash.value},');
    note(3, platform.orientation.source);
    line(3, 'orientation: OrientationPolicy.${platform.orientation.value},');
    note(3, platform.deepLinks.source);
    line(3, 'deepLinks: ${platform.deepLinks.value},');
    note(3, platform.push.source);
    line(3, 'push: ${platform.push.value},');
    final window = platform.window;
    if (window != null) {
      note(3, window.source);
      line(3, 'window: WindowFacts(');
      line(4, 'initial: ${_sizeSpec(window.value.initial)},');
      final min = window.value.min;
      if (min != null) line(4, 'min: ${_sizeSpec(min)},');
      line(3, '),');
    }
    line(2, '),');
  }
  line(1, '},');

  final dartEnv = [
    for (final e in decl.env)
      if (!e.nativeOnly) e,
  ];
  if (dartEnv.isNotEmpty) {
    line(1, 'env: [');
    for (final e in dartEnv) {
      note(2, 'manifest');
      line(2, 'EnvRule(');
      line(3, 'key: ${dartString(e.key)},');
      line(3, 'value: String.fromEnvironment(${dartString(e.key)}),');
      if (e.requiredIn.isNotEmpty) {
        line(
          3,
          'requiredIn: {${e.requiredIn.map((f) => 'Flavor.$f').join(', ')}},',
        );
      }
      line(2, '),');
    }
    line(1, '],');
  }

  line(1, 'capabilities: {');
  for (final entry in view.catalog.optional) {
    final declared = view.capability(entry.id);
    if (declared == null) continue; // refused by `checks.dart`
    note(
      2,
      entry.bundle != null
          ? 'manifest (bundle `${entry.bundle}`, expanded)'
          : 'manifest',
    );
    if (declared.provided) {
      line(2, "'${entry.id}': CapabilityExpectation.provided(),");
    } else {
      line(2, "'${entry.id}': CapabilityExpectation.absent(");
      for (final piece in _splitString(declared.reason ?? '')) {
        line(3, piece);
      }
      line(2, '),');
    }
  }
  line(1, '},');

  final ssl = deriveSslDecisions(view);
  if (ssl.isEmpty) {
    note(1, 'n/a: no declared platform can pin TLS');
    line(1, 'sslPinning: SslPinningPolicy.none(),');
  } else {
    line(1, 'sslPinning: SslPinningPolicy({');
    for (final entry in ssl.entries) {
      note(2, entry.value.source);
      line(2, 'Flavor.${entry.key}: ${_sslCall(entry.value.value, 2)},');
    }
    line(1, '}),');
  }
  line(0, ');');
  return b.toString();
}

/// `SizeSpec(1280, 800)`: a number the manifest wrote as `1280.0` stays a
/// double, one it wrote as `1280` an int — both are valid `double` arguments.
String _sizeSpec(SizeDecl size) => 'SizeSpec(${size.width}, ${size.height})';

String _sslCall(SslDecl decision, int indent) {
  final pad = '  ' * (indent + 1);
  final b = StringBuffer();
  if (decision.isPinned) {
    final pins = decision.pins!;
    b.writeln('SslPinning.pinned(');
    b.writeln('$pad${dartString(pins[0])},');
    b.writeln('$pad${dartString(pins[1])},');
    if (pins.length > 2) {
      b.writeln(
        "$pad[${pins.skip(2).map(dartString).join(', ')}],",
      );
    }
    b.write('${'  ' * indent})');
  } else {
    b.writeln('SslPinning.disabled(');
    for (final piece in _splitString(decision.disabledReason!)) {
      b.writeln('$pad$piece');
    }
    b.write('${'  ' * indent})');
  }
  return b.toString();
}

/// [value] as a Dart single-quoted string literal.
String dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// [value] as one literal per line — adjacent strings, each short enough that
/// the formatter leaves the call alone — the last carrying the trailing comma.
List<String> _splitString(String value) {
  const width = 60;
  final words = value.split(' ');
  final chunks = <String>[];
  var current = '';
  for (final word in words) {
    final next = current.isEmpty ? word : '$current $word';
    if (current.isNotEmpty && next.length > width) {
      chunks.add('$current ');
      current = word;
    } else {
      current = next;
    }
  }
  chunks.add(current);
  final lines = [for (final c in chunks) dartString(c)];
  lines[lines.length - 1] = '${lines.last},';
  return lines;
}
