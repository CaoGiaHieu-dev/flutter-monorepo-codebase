# Composing and Configuring an App

## Goal

You read an app and know what it composes, what it registers, what each platform enables and what it may intervene in. You change any of that in the one file that owns it, add a platform, a capability, a pin, a language or a hook, and create a third app with one command.

## Prerequisites

- A full checkout that builds — [`../getting-started/01_setup.md`](../getting-started/01_setup.md).
- **How the shell boots and what it resolves from an app** — validate, register, DI, check; the contract catalog; the hooks — [`../architecture/06_app_shell.md` § 2](../architecture/06_app_shell.md#2-boot-lifecycle). This guide is the how-to; that page is the why.
- The rules this guide serves: RULE-80 (everything per-app is declared in `apps/<id>/`), RULE-81 (every optional contract has a declared state), RULE-82 (platform differences are an app decision) — [`../reference/01_rules.md` § 21](../reference/01_rules.md#21-apps-and-composition).

---

## 1. Read an app in ten minutes

Every `apps/<id>/` carries its own reading path, and the first stop is generated from the manifest, so it cannot disagree with it:

1. **`README.md`, the report region** — what the app is: identity and flavors, the platforms and what each enables (each cell reads `value (source)`: `manifest`, `default` or `derived: why`), the composition in boot order with the reason for each group, what the shell resolves from the app (required rows, optional rows, which package implements each, what happens if one is absent), and the decisions to revisit before shipping.
2. **`app_manifest.yaml`** — the declaration, and the composition: what the app *is* and what it *composes*.
3. **`lib/app/app_profile.dart`** — the generated `facts` region (the manifest as const Dart) and the hand-written `appProfile`, how the shell *behaves* for this app.
4. **`lib/app/app_hooks.dart`** — the code the app runs at fixed points of the boot.

```bash
dart tools/composer/composer.dart describe --app <id>   # the report on stdout (the text of the README region)
dart tools/composer/composer.dart describe --catalog    # every manifest key, the shell's contract catalog, the derived defaults
dart tools/composer/composer.dart list                  # every app: flavors, platforms, DI groups
```

`describe --catalog` is the key reference: the table of manifest keys it prints is the same table the parser validates against, so this guide does not copy it and cannot go stale against it.

## 2. Four channels, one rule

| Channel | Holds | Lives in |
|:--|:--|:--|
| Manifest | facts a tool must see before code compiles: identity, flavors (and the SSL pin decision each carries), env keys, platforms and what each enables, capabilities, composition | `app_manifest.yaml`, generated into the `facts` region of `lib/app/app_profile.dart` |
| Profile | how the shell behaves: display, router, locale, theme, network limits | `lib/app/app_profile.dart`, below the generated region |
| Hooks | code at fixed points of the boot | `lib/app/app_hooks.dart` |
| Contracts | `core_di` interfaces the app or a module registers, which the shell resolves | modules, and `lib/app/*.dart` for what the app implements itself |

**The rule:** the manifest says what the app **is** and where it runs; the profile says how the shell **behaves**; hooks are **code**. Everything per-platform is in the manifest, so the effective platform matrix is derivable and printed. Everything that is a tuning number is typed Dart, so no YAML engine sits between you and a value. Pick the channel by asking whether a gate must read it before code compiles (manifest), whether it is a value (profile) or whether it is behaviour (hook).

## 3. The manifest

```yaml
app:
  id: admin
  name: Codebase Admin
  entrypoint: lib/main.dart

flavors:                       # closed set: dev | staging | prod
  dev:
  staging:
  prod:                        # ssl_pinning only where a declared platform can pin

env:
  BASE_URL: { required_in: [prod] }
  APP_NAME: { }                # optional: the title falls back to app.name

platforms:
  windows: { runner: scaffold }
  web:     { runner: scaffold }

capabilities:
  session: provided
  splash:  { state: absent, reason: "native splash is kept through boot" }
  # … one entry per optional contract of the catalog

di_groups: [ … ]               # ordered; `why:` records the reason for the slot
modules:
  - { id: auth,     layers: [api, domain, data, feature] }
  - { id: settings, layers: [feature] }
```

| Section | Says | Read by |
|:--|:--|:--|
| `app` | the id (the folder, the package `<id>_app`, every `--app`), the display name, the entry point | the boot check (the id), the `MaterialApp` title (the name; `APP_NAME` overrides it per flavor), `describe`, `verify` (V12) |
| `flavors` | which of `dev`, `staging`, `prod` the app is built as; each may carry an `ssl_pinning` decision | the facts, `validate` (`P02`), the smoke test |
| `env` | the `--dart-define` keys the app reads, and the flavors that require each; `native_only: true` for a key only Gradle or Xcode reads | `validate` (`P03`), V11 |
| `platforms` | where the app runs, and per platform: `runner`, `splash`, `push`, `deep_links`, `orientation`, `window` | the facts, `validate` (`P01`, `P05`), V5–V8 |
| `capabilities` | `provided`, or `absent` with a reason, for every optional contract the shell resolves | `checkAppContract`, V2–V4, V14 |
| `di_groups`, `modules`, `extra_dependencies` | what the app composes, in what order and why | `sync`, `injection.dart`, the app's path dependencies |

A key exists only together with the code that reads it: a tools test fails when a key names a consumer that does not mention it. `composer` refuses `app.kind`, which nothing reads, with the instruction to delete the line.

Where a platform leaves `splash`, `push`, `deep_links` or `orientation` out, the generated facts carry a derived default, and the report says which: `splash` is native on iOS and, elsewhere, Dart when capability `splash` is provided; `push` is on when `core_notifications` is composed and supports the platform (never on the web — no service worker ships); `deep_links` is on; `orientation` is `phones_portrait` (displays under the phone threshold locked to portrait). The facts always carry every field explicitly, so an app never depends on a Dart default.

## 4. The profile

`lib/app/app_profile.dart` holds the generated `facts` region and, below it, the hand-written profile. Each section is a typed `const` with defaults equal to the template's behaviour, and a section you leave out is that default. The type documents its own ranges; this table says where to look and what the default is.

| Section | Type | Tunes | Default |
|:--|:--|:--|:--|
| `display` | `DisplayProfile` | design artboard, scale policy per window class, split-screen mode, the OS font-size cap, the phone threshold | 375×812, `expanded` drawn 1:1, `textScaleMax: 2.0` (a `const` assert refuses less than 2.0 and more than 4.0), phone threshold 600 |
| `router` | `RouterProfile` | when the entry location is used (`firstLaunch`, `always`, `never`), the fallback location | first launch only, first tab |
| `locale` | `LocaleProfile` | the languages offered (`supported`; null = every ARB the template ships), the fallback and the first-launch language | every shipped language, `en`, the device's language |
| `theme` | `ThemeProfile` | the theme mode a first launch opens in, palette overrides by `PaletteToken` (ARGB) | system mode, the template palettes |
| `network` | `NetworkProfile` | the default HTTP client's connect, receive and send timeouts, extra headers, redirects | 20 s each, no extra headers, no redirects |

```dart
const AppProfile appProfile = AppProfile(
  facts: appFacts,
  display: DisplayProfile(
    designSize: SizeSpec(1440, 900),
    textScaleMax: 2.5,
    scale: {
      WindowClass.expanded: ScalePolicy.fixed(),
      WindowClass.large: ScalePolicy.fixed(),
    },
  ),
  locale: LocaleProfile(supported: ['vi'], fallback: 'vi', initial: 'vi'),
  theme: ThemeProfile(
    mode: ThemeModeSetting.dark,
    dark: {PaletteToken.primary: 0xFFF97316},
  ),
  network: NetworkProfile(
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 60),
    headers: {'x-client': 'reports'},
  ),
);
```

What a section cannot say is refused where it can be: `DisplayProfile(textScaleMax: 1.5)` does not compile (`const_eval_throws_exception` — RULE-38), a `NetworkProfile` header named `authorization`, `cookie`, `set-cookie`, `proxy-authorization` or `content-type` makes the default client throw at boot (RULE-66), and a `LocaleProfile` that offers no shipped language or whose fallback it does not offer throws at boot naming the field. The palette's `shadow` and `scrim`, and the two gradients, are not overridable: the gradients derive from `primary`, `primaryContainer`, `info` and `error`.

After editing the profile run `composer sync`: the README report's § 5 prints the sections the app sets, and `verify` (V13) re-reads the file to keep it current. Each app's `test/app_profile_test.dart` is where you assert what you changed, so a later edit that moves it is visible. What each section means for a screen: [`09_localization_theming.md`](09_localization_theming.md) (`locale`, `theme`) and [`11_design_system.md`](11_design_system.md) (`display`, `theme`).

## 5. Hooks

```dart
// lib/app/app_hooks.dart
import 'package:core_common/core_common.dart'; // AppRuntime, WindowFacts
import 'package:platform_app_shell/platform_app_shell.dart';

const ShellHooks appHooks = ShellHooks(
  beforeDependencies: _initCrashReporting, // a top-level function: const
  configureWindow: _sizeTheWindow,
);

Future<void> _initCrashReporting(AppRuntime runtime) async {
  // e.g. SentryFlutter.init — runs before DI; nothing can be resolved yet.
}

Future<void> _sizeTheWindow(AppRuntime runtime, WindowFacts window) async {
  // Apply window.initial / window.min with the app's own window plugin.
}
```

A hook that names `AppRuntime` or `WindowFacts` needs the `core_common` import, which the generated file does not carry. Type `const ShellHooks(` and the IDE lists the seven hooks, each documented with when it runs and what it may not do: `onError`, `onNonFatalError`, `beforeDependencies`, `afterBoot`, `navigatorObservers`, `redirect`, `configureWindow` (the table is in [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md#hooks)). A hook that throws is reported like any error in the app zone and stops the boot where it ran. The template ships no window plugin (RULE-74: the catalog gains one only when an app adopts it), so an app that wants a desktop window size adds the plugin to its own dependencies.

## 6. Contracts: what the shell asks of an app

The shell resolves its contracts through one catalog, `SHELL_CONTRACTS` (`platform/shell/app_shell/lib/src/utils/shell_contract_constants.dart`): **required** rows the shell's own packages register — an app composes the `shell` and `ui` groups and gets them — and **optional** rows an app or a module contributes (`describe --catalog` prints the live table). An app declares each optional row, and `describe --catalog` lists them with what the shell does without each:

```yaml
capabilities:
  session: provided      # a bundle: ISessionState, ISessionGateway, ISessionRefreshListenable, ISignInLocation
  error_reporter:
    state: absent
    reason: "no crash backend chosen: errors are printed and sent nowhere (RULE-67)"
```

Absence is a decision with a reason: `composer verify` refuses an empty, `TODO` or `TBD` reason (V14), and the report lists an absent `error_reporter` or `analytics` under *decisions to revisit before shipping*. A contract the app implements itself — a crash reporter — is a class under `lib/app/`:

```dart
@LazySingleton(as: IErrorReporter)
class CrashlyticsErrorReporter implements IErrorReporter { … }
```

After that, declare it `provided`. Declaring a contract the code does not register, or registering one the manifest says is absent, fails at three places: `composer verify` (V3, statically, naming the file), the smoke test (`checkAppContract`, from the graph the app builds) and the boot of a dev or staging flavor or a debug build, which `checkAppContract` runs after DI.

Tabs have one more rule. An app that composes **two or more** `INavDestinationModule`s needs a `dashboard` (`IDashboardRouteModule`, the sample is `feature_dashboard`): it draws the chrome that switches between tabs, and without it only the first tab is reachable. `checkAppContract` says so (`C12`) in the smoke test and in a debug boot. One tab renders fine without a dashboard (`apps/admin`). To add the dashboard: `- { id: dashboard, layers: [feature] }` under `modules:`, `dashboard: provided` under `capabilities:`, then `composer sync`.

What an app must register for a package it composes — `FirebaseOptions` for `core_notifications`, one per flavor — is listed in the report under *This app must provide*, and V10 fails if it is missing. Native settings (`google-services.json`, `aps-environment`) are documented there and not checked.

## 7. Recipes

### Add a platform

1. See what blocks it: the report's *Not targeted — and what blocks it* names every composed package whose pubspec `platforms:` does not list it (`core_database` has no web, `core_notifications` no Windows or Linux).
2. Declare it, runner still to be created: `platforms.<p>: { runner: scaffold }`, then `dart tools/composer/composer.dart sync --app <id>`.
3. Create the runner once, with the line the report prints, e.g. `cd apps/<id> && flutter create --platforms=windows --org com.example --project-name <id>_app .` (put your own reverse domain in `--org`: a platform that has an application or bundle ID builds it from this value), and change the declaration to `runner: committed`. A declared `committed` runner needs its folder, a `scaffold` one must not have it (V6).
4. Set what the platform enables, if the default is not right: `push`, `deep_links`, `orientation`, and for a desktop platform `window: { initial: [1440, 900], min: [1024, 700] }`, which needs the `configureWindow` hook (`P05` otherwise). A platform that switches push or deep links off logs one line naming the key and initialises nothing.
5. Run `composer verify` and the smoke test. On the web there is no `--flavor` option: pass `--dart-define=APP_FLAVOR=<flavor>` — the Flutter tool refuses the framework's own `FLUTTER_APP_FLAVOR`, and the shell reads `APP_FLAVOR` on the web only.

### Pin certificates

Pinning works on Android and iOS only — the browser owns TLS on the web, and the pinning plugin has no desktop implementation — so the key is required only where a declared platform can pin, and refused where none can. Replace the staging or prod decision in the manifest:

```yaml
flavors:
  prod:
    ssl_pinning: { pins: ["<leaf spki sha256 base64>", "<backup spki sha256 base64>"] }
```

At least two pins, each the base64 of 32 bytes (V9). How to compute them: [`08_networking.md` § 10](08_networking.md#10-turn-on-ssl-pinning). A flavor that deliberately does not pin says `ssl_pinning: { disabled: "reason" }`, and the report lists it under the decisions to revisit.

### Add or remove a module

Add the line to `modules:` and run `sync`. If the module registers a catalogued contract, `verify` now says so — *declared absent but ISessionState is registered at …* — and you declare it `provided`. Remove one and `verify` names the key that lost its provider and prints the `absent` line to paste. `dart tools/sample_cleanup/remove_sample.dart <bundle> --apply` does both flips for the sole providers and runs `sync` itself.

### Offer other languages, change the palette or the limits

Set `locale`, `theme` or `network` in `appProfile` (section 4). A new language is an ARB in `core_base_ui` and in each feature ([`09_localization_theming.md`](09_localization_theming.md)); an app that names no `supported` list offers every shipped language, one that names a list keeps its list. A `LocaleProfile.fallback` the list does not contain is refused at boot.

### Add a hook

Add the field to `appHooks` (section 5). A value that fits the manifest or the profile belongs there instead, where a gate can read it.

## 8. A third app by command

```bash
dart tools/composer/composer.dart new reports --name "Codebase Reports" --platforms web,windows --modules auth,settings
```

The command renders `tools/composer/app_template/` into `apps/<id>/`: the manifest, `pubspec.yaml`, a `README.md` with the reading path, `lib/main.dart`, `lib/app/app_profile.dart` and `app_hooks.dart`, `lib/di/injection.dart`, a smoke test and a profile test, `env.dev` and `.gitignore`. It derives `capabilities:` from what the requested modules register — `provided` where something registers the contract, otherwise `absent` with what the shell does without it as the reason, never `TODO` — then runs `sync` and `verify`, so the app passes Gate 0 at once.

- It refuses, and writes nothing, for an id that is already an app, a platform a requested module blocks (`--platforms web` with a module that opens a database), an unknown module or platform, or a name that would break the files it is written into.
- It **never runs `flutter create`**: each platform is `runner: scaffold`, and the command prints the line to run when you want the runner.
- It does not compose `core_notifications` (push needs `FirebaseOptions` and a `notifications` group — copy `apps/mobile`'s pattern), and an app that links `core_database` copies `apps/mobile`'s smoke-test doubles.

Then, from the repository root: `flutter pub get`, `dart run build_runner build --workspace`, `cd apps/<id> && flutter test`. The two files you edit to make the app differ are `apps/<id>/app_manifest.yaml` and `apps/<id>/lib/app/app_profile.dart`; nothing under `platform/`, `modules/` or another app changes.

## 9. What Gate 0 checks

`composer verify` regenerates every generated file and fails on drift (V13), and holds the declaration to the source: the vocabularies and ranges (V1, V14), the capability states against what the composed packages and the app register (V2–V4), the platform switches against what the app composes and what each package supports (V5–V8), the pin decision per flavor (V9), what a composed package needs the app to register (V10), the env files (V11), the entry point and the smoke test (V12), the native runners (V6, V15), the DI group order (V16) and the single workspace node (V17, RULE-16). `dart tools/composer/composer.dart describe --catalog` prints the live list of checks; this guide does not copy it.

Read a message from left to right: `<file>: <key>: <problem> — <the fix>`. The scan behind V3 and V10 reads source, not the graph — a hand-written `getIt.register…` is invisible to it — so `checkAppContract` stays the authority. V3, V10, V11, V12 and V17 fail `verify` while `sync` only warns and still writes, so a half-finished edit can be regenerated; V7 and V8 refuse in both, before anything is written.

## 10. What stays locked, and one DI caveat

Changing these means editing the shared package, for every app: breakpoints, component themes, page transitions, the default `Dio` interceptor chain and retry policy, the 404 page, the shadow and scrim colours, push channel and icon, deep-link allow-lists, logger limits, the system-UI overlay and secure-storage options. The report's last section lists them.

Replacing a shell-owned type by registration order is unsupported. `enableRegisteringMultipleInstancesOfOneType()` — generated into `configureDependencies` — makes GetIt keep the **first** registration of a type, so an app registration beats a type registered in an `after` group and loses to one in the `before` group, whose eager original still runs. The profile and the hooks are the seams that remove the reasons people reached for it.

---

## Verify

```bash
dart tools/composer/composer.dart verify                 # Gate 0 — the declaration, the generated regions, the source
dart tools/composer/composer.dart describe --app <id>    # the report reads as you intend
dart tools/arch_check/check.dart                         # R16 (catalog complete), R17 (platform forks)
cd apps/<id> && flutter test                             # the smoke test (checkAppContract per flavor) and the profile test
```

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `verify`: `declared provided but no composed package or apps/<id>/lib registers …` | A module was removed, or never composed, while the manifest says `provided` | Add the module, or declare the contract `absent` with a reason (the message prints the line) |
| `verify`: `declared absent but … is registered at <file>:<line>` | A composed package registers it | Declare it `provided`, or stop composing what registers it |
| `verify`: `out of date: … (facts)` | The manifest changed, or the generated region was edited by hand | `dart tools/composer/composer.dart sync --app <id>`; never edit a `composer:managed` region (RULE-16) |
| `verify`: `flavors.prod.ssl_pinning: decide …` | A flavor of an app with an Android or iOS platform has no pin decision | `pins: [...]` or `disabled: "reason"` (above) |
| `verify`: `<package> does not support <platform>` | A composed package, or one it links, lacks the platform | Declare only platforms every linked package supports, or stop depending on it |
| Boot stops: *`<id>` is running on `<platform>`, which its manifest does not declare* | The platform is not under `platforms:` | Declare it (above), run on a declared one, or `--dart-define=ALLOW_UNDECLARED_PLATFORM=true` for a quick look |
| Boot stops: `P03` on a release build | A required `--dart-define` is empty | Pass `--dart-define-from-file=env.<flavor>` |
| Boot stops on a desktop platform: `P05` | `window` is declared and no `configureWindow` hook is set | Add the hook (section 5), or drop the `window` |
| Smoke test: `C02` / `C03` | The graph disagrees with the declaration | The test names the contract — fix the manifest or the composition |
| `new` refuses | The id exists, or a platform is blocked by a module | The message names which; nothing was written |
| `flutter analyze`: `const_eval_throws_exception` on a `DisplayProfile` | `textScaleMax` below 2.0, or a `SizeSpec` with a non-positive side | Use 2.0 or more (RULE-38) |

## Related

- Rules: RULE-80, RULE-81, RULE-82, RULE-16 (generated regions), RULE-48 (pinning), RULE-63 (the smoke test), RULE-67 (reporters) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/06_app_shell.md`](../architecture/06_app_shell.md) — the boot, the catalog and the hooks, and why
- [`05_di.md`](05_di.md) — registering a type and composing a package
- [`../reference/03_tooling.md`](../reference/03_tooling.md) — `composer`, `arch_check` R16/R17 and the other tools
- Skill: `.claude/skills/configure_app`
