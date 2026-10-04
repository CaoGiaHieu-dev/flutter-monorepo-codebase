---
name: localize_feature
description: Use when a screen shows text the user reads — "add a translated string", "translate this feature", "add an ARB key", "the l10n getter does not exist", "add Vietnamese", "show an error message", "add a language". Covers the feature's ARB files (en and vi, lowerCamelCase keys), flutter gen-l10n, the IFeatureLocalization delegate and the context.l10n<Name> extension, failure text from error codes, global strings in core_base_ui, and what a new locale touches.
---

# Skill: Localize a feature

Use this skill whenever the UI gains or changes user-facing text, a feature gets its translations, or a language is
added. Every user-facing string is translated — toasts, dialogs, error messages and button labels included.

**Guide:** [`docs/en/guides/09_localization_theming.md`](../../../docs/en/guides/09_localization_theming.md) § 1–2;
how the delegates reach `MaterialApp`: [`06_app_shell.md` § 7](../../../docs/en/architecture/06_app_shell.md#how-feature-translations-reach-materialapp).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-34, RULE-35, RULE-36, RULE-37, RULE-62.
Cite them; do not restate them.

## Where a string goes

| String | Lives in | Read with |
| :--- | :--- | :--- |
| Belongs to one feature | that feature's `assets/language/en.arb` **and** `vi.arb` | `context.l10n<Name>.<key>` |
| Genuinely global (shared labels, generic failures, language names) | `platform/ui/design_system/assets/language/` (`core_base_ui`) | `context.l10n.<key>` |
| Inside a `core_ui_kit` widget | `core_base_ui`'s ARB — `core_ui_kit` has **no** ARB | `context.l10n.<key>` |
| A failure's text | never `AppFailure.message` (developer text) | `context.l10n.failureMessage(failure.code)` |

A feature that can say more than the generic fault (wrong password, unknown user) classifies the failure itself and
uses its own key; the generic form is shown in `modules/home/feature/lib/src/pages/home_page.dart`. A feature's
assets live in the feature's `assets/` (RULE-37).

## Steps

### Step 1: Add the keys to every locale file

The generator wrote `modules/<name>/feature/assets/language/en.arb` and `vi.arb` (with a `title` key); `vi.arb`
starts as a copy of the English text. ARB is **strict JSON** — no `//` comment, no trailing comma. Keys are
`lowerCamelCase` (RULE-35). Add the same key to **every** locale file, and write natural Vietnamese in `vi.arb`
(technical terms and identifiers stay English):

```json
{
  "@@locale": "en",
  "title": "Profile",
  "emptyProducts": "No products yet",
  "refreshProducts": "Refresh"
}
```

### Step 2: Generate the Dart code

```bash
cd modules/<name>/feature && flutter gen-l10n
```

`build_runner` does not read ARB files; `gen-l10n` follows the package's `l10n.yaml` (`arb-dir: assets/language`,
template `en.arb`, output class `Feature<Name>Localizations`, output `lib/src/gen/language`, `preferred-supported-locales: [en, vi]`).
Each feature has its **own** `output-class` so delegates never collide. Missing translations are listed in
`untranslated-messages.txt`; it must be empty. `dart tools/workspace_setup/configure.dart` runs `gen-l10n` for every
package that has an `l10n.yaml`. The output is generated and gitignored, but the package barrel exports it once it is
on disk: regenerate the barrel afterwards ([`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator)).

### Step 3: Use the string — the delegate and extension already exist

The generator wires both, once per feature; check they are there rather than adding a second:

```dart
// lib/src/localization/<name>_localization_impl.dart — the shell collects every IFeatureLocalization
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate => FeatureHomeLocalizations.delegate;
}

// lib/src/extensions/l10n_<name>_extension.dart
extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

```dart
Text(context.l10nHome.userLoggedIn)
```

Never register a delegate by editing the shell's `app_material_wrapper.dart`: it collects the delegates from DI
(RULE-34). A feature composed into an app contributes its strings with nothing else to touch.

### Step 4: A failure message

```dart
error: (failure) => Text(context.l10n.failureMessage(failure.code)),
```

`failureMessage` is `core_base_ui`'s mapping from a failure's `code` (an `ErrorCodes` value or an HTTP status) to a
translated sentence. Carry the **code** to the screen, not the message (the Provider branch in
[`implement_provider_ui`](../implement_provider_ui/SKILL.md), the BLoC branch in
[`implement_bloc_ui`](../implement_bloc_ui/SKILL.md)).

### Step 5: Dialogs and sheets are widget classes

A dialog or bottom sheet that shows these strings is its own class in its own file (`*_dialog.dart` →
`…Dialog`, `*_bottom_sheet.dart` → `…BottomSheet`), never an inline builder (RULE-36); `RetryDialog` in
`core_ui_kit` is the example.

### Step 6: Test it

A widget test of a localized page wraps it in `ResponsiveInit` and passes the feature's delegates, as the generated
`test/<name>_page_test.dart` does (`<Pascal>Localizations.localizationsDelegates` and `.supportedLocales`, RULE-62).
Read the expected text from the localizations, not a literal.

## Add a language

Adding a locale touches `core_base_ui` **and every feature that ships strings**, not just yours: an ARB in
`platform/ui/design_system/assets/language/` and in each feature with an `l10n.yaml` (`find modules -name l10n.yaml`), the language's display name
in every `core_base_ui` ARB and in `AppLanguages.nameOf`, and `preferred-supported-locales` in each `l10n.yaml`. A feature
with no ARB for a language makes `FeatureXLocalizations.of(this)!` return `null`, so the first `context.l10nX` after the
user picks it throws; the app's DI smoke test fails on such a feature. Which apps offer the language is the app's
`LocaleProfile` in `apps/<id>/lib/app/app_profile.dart` ([`configure_app`](../configure_app/SKILL.md)). The generator's
templates (`tools/module_generator/templates/feature/localization/`) ship only `en` and `vi`: extend them too. Full
steps: [guide 09 § 2](../../../docs/en/guides/09_localization_theming.md#2-add-a-locale).

## Related

- [`docs/en/guides/09_localization_theming.md`](../../../docs/en/guides/09_localization_theming.md) — tokens, responsive sizing, adding a locale in full
- [`create_feature_module`](../create_feature_module/SKILL.md) — the generator that writes the l10n scaffold

## Verify

```bash
cd modules/<name>/feature && flutter gen-l10n            # then check untranslated-messages.txt is empty
dart tools/unused_checker/check_unused_translate.dart    # advisory: keys no code uses (exit 2 = findings)
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R7 / R20: no raw layout number beside the new text; R21: every ARB has en.arb's keys
dart tools/composer/composer.dart verify
cd modules/<name>/feature && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # every feature delegate supports every language the app offers
```

On a device, switch the language in Settings: every string on the screen must follow.
