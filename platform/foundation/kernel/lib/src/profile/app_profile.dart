import '../flavor.dart';
import 'app_facts.dart';
import 'app_platform.dart';
import 'display_profile.dart';
import 'locale_profile.dart';
import 'network_profile.dart';
import 'profile_problem.dart';
import 'router_profile.dart';
import 'theme_profile.dart';

/// Everything an app tells the shell about itself.
///
/// [facts] is generated from the manifest; the app's own
/// `lib/app/app_profile.dart` wraps it in a `const AppProfile`, and
/// `runShellApp` registers it (`registerAppProfile`) before dependency
/// injection starts, so anything built during DI can read it.
///
/// The split: [facts] say what the app *is* and where it runs (generated from
/// the manifest, which tools read before any code compiles); the sections
/// beside it say how the shell *behaves* (typed const Dart, defaults equal to
/// the template's own behaviour). An app that sets no section is the template.
final class AppProfile {
  const AppProfile({
    required this.facts,
    this.display = const DisplayProfile(),
    this.router = const RouterProfile(),
    this.locale = const LocaleProfile(),
    this.theme = const ThemeProfile(),
    this.network = const NetworkProfile(),
  });

  /// What the app is and where it runs. Generated from the manifest.
  final AppFacts facts;

  /// The design artboard, scale policy and OS font-size cap.
  final DisplayProfile display;

  /// Where the router starts and where it falls back to.
  final RouterProfile router;

  /// The languages the app offers, its fallback and its first-launch language.
  final LocaleProfile locale;

  /// The theme mode the app opens in and its palette overrides.
  final ThemeProfile theme;

  /// The timeouts, extra headers and redirect policy of the default HTTP
  /// client.
  final NetworkProfile network;

  /// The problems with starting this app on [platform] in [flavor] — pure and
  /// pre-DI, so the shell can stop before any dependency is built.
  ///
  /// - `P01` — [platform] is not declared in the manifest;
  /// - `P02` — [flavor] is not declared;
  /// - `P03` — a required environment key is empty in [flavor] (skipped when
  ///   [checkEnv] is false, as a test that boots without `--dart-define`s);
  /// - `P04` — [flavor] has no SSL pinning decision on a platform that can
  ///   pin TLS;
  /// - `P05` — the platform declares a `window` and [hasWindowHook] is false:
  ///   a declared window is never a silent no-op.
  ///
  /// A problem whose subject is undeclared is not repeated as a second one:
  /// with `P01` the platform's own facts are not inspected, with `P02` the
  /// flavor's environment keys and pin decision are not.
  List<ProfileProblem> validate({
    required AppPlatform platform,
    required Flavor flavor,
    bool checkEnv = true,
    bool hasWindowHook = false,
  }) {
    final id = facts.id;
    final manifest = 'apps/$id/app_manifest.yaml';
    final sync = 'dart tools/composer/composer.dart sync --app $id';
    final problems = <ProfileProblem>[];

    final platformFacts = facts.platformFor(platform);
    if (platformFacts == null) {
      problems.add(
        ProfileProblem(
          code: 'P01',
          description:
              'Boot stopped: `$id` is running on ${platform.name}, which its '
              'manifest does not declare (declared: '
              '${_names(facts.platforms.keys)}).',
          action:
              'Add `${platform.name}:` under `platforms:` in $manifest and '
              'run `$sync`; or run on a declared platform; or pass '
              '--dart-define=ALLOW_UNDECLARED_PLATFORM=true for a quick '
              'look.',
        ),
      );
    }

    final flavorDeclared = facts.flavors.contains(flavor);
    if (!flavorDeclared) {
      problems.add(
        ProfileProblem(
          code: 'P02',
          description:
              'Boot stopped: `$id` is built as flavor `${flavor.name}`, which '
              'its manifest does not declare (declared: '
              '${_names(facts.flavors)}).',
          action:
              'Add `${flavor.name}:` under `flavors:` in $manifest and run '
              '`$sync`; or build a declared flavor with `--flavor <name>` '
              '(on the web: `--dart-define=FLUTTER_APP_FLAVOR=<name>`).',
        ),
      );
    }

    if (flavorDeclared && checkEnv) {
      for (final rule in facts.env) {
        if (rule.requiredIn.contains(flavor) && rule.value.isEmpty) {
          problems.add(
            ProfileProblem(
              code: 'P03',
              description:
                  'Boot stopped: `${rule.key}` is required in flavor '
                  '`${flavor.name}` (env.${rule.key}.required_in in '
                  '$manifest) but this build defines it empty.',
              action:
                  'Define it: add `${rule.key}=<value>` to the env file passed '
                  'with --dart-define-from-file, or pass '
                  '--dart-define=${rule.key}=<value>.',
            ),
          );
        }
      }
    }

    if (platformFacts != null) {
      if (flavorDeclared &&
          platform.canPinTls &&
          facts.sslPinning.decisionFor(flavor) == null) {
        problems.add(
          ProfileProblem(
            code: 'P04',
            description:
                'Boot stopped: flavor `${flavor.name}` has no SSL pinning '
                'decision in $manifest, and ${platform.name} can pin TLS '
                'certificates.',
            action:
                'Decide it under `flavors.${flavor.name}.ssl_pinning` in '
                '$manifest — `pins: ["<leaf spki sha256 base64>", '
                '"<backup spki sha256 base64>"]` or `disabled: "<reason>"` — '
                'and run `$sync`.',
          ),
        );
      }

      if (platformFacts.window != null && !hasWindowHook) {
        problems.add(
          ProfileProblem(
            code: 'P05',
            description:
                'Boot stopped: ${platform.name} declares a `window` in '
                '$manifest, but the app has no window hook to apply it.',
            action:
                'Pass a window hook in `ShellHooks` (the shell hands it the '
                'declared sizes and brings no window plugin), or remove '
                '`window:` from `platforms.${platform.name}` in $manifest and '
                'run `$sync`.',
          ),
        );
      }
    }

    return problems;
  }
}

/// [values] by declaration order, comma-separated; `none` for no value.
String _names(Iterable<Enum> values) {
  final sorted = values.toList()..sort((a, b) => a.index.compareTo(b.index));
  return sorted.isEmpty ? 'none' : sorted.map((v) => v.name).join(', ');
}
