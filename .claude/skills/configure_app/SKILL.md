---
name: configure_app
description: Use when changing what an app is or how the shell behaves for it — "add a platform", "turn push or deep links off on web", "pin certificates", "offer other languages", "change the palette, text-scale cap, design size or HTTP timeouts for one app", "add a hook", "declare a capability absent", "what does this app register?", or "create a third app". Picks the right channel (manifest, profile, hook, contract), edits it, runs composer sync and verify, and proves it with the smoke test. Declares capabilities by decision; remove_module reconciles them after a removal and implement_dependency_injection registers the contract.
---

# Skill: Configure an app

Use this skill when a per-app decision must change, or when asked to read an app, or to create one.
Nothing per-app is ever a constant in `platform/` (RULE-80).

> **Capabilities have three owners.** Declaring one `provided` or `absent` by decision is this skill. Flipping the ones that lost
> their last provider after a removal is [`remove_module`](../remove_module/SKILL.md) (`composer reconcile`). Registering the
> contract itself is [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md). `composer verify` (V3) names
> both sides when a registration and a declaration disagree.

**Guide:** [`docs/en/guides/13_app_composition.md`](../../../docs/en/guides/13_app_composition.md) ·
architecture: [`06_app_shell.md` § 2](../../../docs/en/architecture/06_app_shell.md#2-boot-lifecycle).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-80, RULE-81, RULE-82, RULE-16,
RULE-38, RULE-48, RULE-63, RULE-67 — cite them, do not restate them.

---

## 1. Read the app first

```bash
dart tools/composer/composer.dart describe --app <id>   # the report: identity, platforms, composition, what the shell resolves, decisions to revisit
dart tools/composer/composer.dart describe --catalog    # every manifest key, the contract catalog, derived defaults, checks, problem codes
```

Then open, in order: `apps/<id>/README.md` (generated report) → `app_manifest.yaml` →
`lib/app/app_profile.dart` → `lib/app/app_hooks.dart`.

## 2. Pick the channel — one question each

| If the change is… | It belongs in | Edit |
|:--|:--|:--|
| a fact a tool must see before code compiles: identity, flavors, a pin decision, env keys, a platform and what it enables, a capability, composition | the **manifest** | `apps/<id>/app_manifest.yaml`, then `composer sync` |
| a tuning value: design size, scale, text-scale cap, router locations, languages, theme mode, palette, HTTP timeouts and headers | the **profile** | `appProfile` in `apps/<id>/lib/app/app_profile.dart` — **below** the generated `facts` region |
| code that must run at a fixed point of the boot | a **hook** | `apps/<id>/lib/app/app_hooks.dart` (`ShellHooks`: `onError`, `onNonFatalError`, `beforeDependencies`, `afterBoot`, `navigatorObservers`, `redirect`, `configureWindow`) |
| something the shell resolves from the app (a crash reporter, analytics) | a **contract** | a class under `apps/<id>/lib/app/` registering the `core_di` interface, then declare it `provided` |

Never edit the `facts` region or the README `report` region (RULE-16: `composer:managed`), never
`injection.dart`, and never a `platform/` package for a value one app wants different.

## 3. Recipes

- **Add a platform.** `platforms.<p>: { runner: scaffold }` → `sync` → run the `flutter create` line the
  report prints, **inside `apps/<id>/`** → change to `runner: committed` → `sync`. The report's *Not
  targeted — and what blocks it* says whether a composed package rules the platform out (V7).
- **Switch a platform feature off / on.** `platforms.<p>.push`, `.deep_links`, `.orientation`
  (`phones_portrait | free | portrait | landscape`), `.splash` (`dart | native`), `.window` (desktop
  only; needs the `configureWindow` hook or boot stops with P05). Left out, the report shows the
  derived default and why.
- **Pin certificates.** `flavors.prod.ssl_pinning: { pins: ["<leaf>", "<backup>"] }` (≥ 2, base64 of 32
  bytes) or `{ disabled: "reason" }` (RULE-48, V9). Only Android and iOS can pin. Pins apply to **every host the
  process connects to** (an image CDN, a font host or an SDK endpoint with no matching pin fails its TLS
  handshake too): check those hosts first — [`08_networking` § 10](../../../docs/en/guides/08_networking.md#10-turn-on-ssl-pinning).
- **Another language / palette / limits.** `locale: LocaleProfile(supported: […], fallback:, initial:)`,
  `theme: ThemeProfile(mode:, light:, dark:)` (17 `PaletteToken`s; `shadow` and `scrim` are not
  overridable), `network: NetworkProfile(connectTimeout: …, authorizedHosts: {…})` (no auth / cookie / content-type
  headers, RULE-66; the bearer token goes only to the `BASE_URL` host and `authorizedHosts`, so a split-domain
  API lists its other hosts there — and pins them), `display: DisplayProfile(textScaleMax: 2.5)` (never below 2.0 — RULE-38, a compile error).
- **Declare a capability.** `capabilities.<id>: provided` or `{ state: absent, reason: "…" }`; the
  reason says why, never `TODO` (V14). `composer verify` (V3) says which direction is wrong.
- **Add an env key.** Under `env:` (`required_in: [flavor…]`, or `native_only: true`) **and** in the
  `env.<flavor>` files (V11).

## 4. A third app

```bash
dart tools/composer/composer.dart new reports --name "Codebase Reports" --platforms web,windows --modules auth,settings
flutter pub get && dart run build_runner build --workspace
cd apps/reports && flutter test
```

`new` writes the manifest (capabilities derived from what the modules register; absent ones carry what
the shell does without them as the reason), profile, hooks, entry point, smoke and profile tests, then
runs `sync` and `verify`. It refuses an existing id or a platform a module blocks before writing, and it
**never runs `flutter create`** — it prints the line. It does not compose `core_notifications` (copy
`apps/mobile`'s `lib/firebase/` and the smoke test's doubles when push is wanted), and an app linking
`core_database` copies `apps/mobile`'s smoke-test doubles. The two files to edit afterwards:
`app_manifest.yaml` and `lib/app/app_profile.dart`.

## Related

- `docs/{en,vi}/guides/13_app_composition.md` — the full guide, the Gate 0 check list, troubleshooting
- `implement_dependency_injection` (registering a contract), `create_feature_module` (a module that
  registers one), `run_repo_tooling` (`describe`, `new`)

## Verify

```bash
dart tools/composer/composer.dart sync --app <id>     # after any manifest edit
dart tools/composer/composer.dart verify              # Gate 0 — declaration vs generated regions vs source
dart tools/arch_check/check.dart                      # R16 (catalog complete), R17 (platform forks)
flutter analyze                                       # 0 issues (RULE-70)
cd apps/<id> && flutter test                          # di_smoke_test (checkAppContract per flavor), app_profile_test
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # a DI or dependency change (RULE-77)
```

A profile value you changed gets a line in `apps/<id>/test/app_profile_test.dart` that says what it changes.
