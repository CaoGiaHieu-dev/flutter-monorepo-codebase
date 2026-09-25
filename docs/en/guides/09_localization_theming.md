# Guide: Localization, Theming & Responsive UI

## Goal

You ship a feature's own translations without touching the app shell, add a locale, style a widget with design tokens, and size it so it scales and adapts. You also keep reusable widgets honest: they take already-scaled values and never re-scale them.

## Prerequisites

- A feature package — [`01_new_feature.md`](01_new_feature.md).
- **How feature translations reach `MaterialApp`** without the shell naming them — [`../architecture/06_app_shell.md` § 7](../architecture/06_app_shell.md#how-feature-translations-reach-materialapp).
- Where every token is defined, and how to change the palette, font or scales: [`11_design_system.md`](11_design_system.md). This guide is about *using* them.

---

## 1. Add a translated string

Where a string goes (RULE-34, RULE-37):

- Every user-facing string goes through a delegate — toasts, dialogs, error messages and button labels included. No hard-coded strings, ever.
- A feature's strings go in that feature's `.arb` files.
- Genuinely global strings go in `core_base_ui`.
- `core_ui_kit` defines **no** `.arb` of its own: it is a widget library every feature uses, and its strings come from `core_base_ui`.

### Edit the ARB files

In `modules/home/feature/assets/language/en.arb` — ARB is plain JSON, so a pasted `//` comment breaks `gen-l10n`:

```json
{
  "@@locale": "en",
  "home": "Home",
  "tabLabel": "Home",
  "userLoggedIn": "User is Logged In",
  "userLoggedOut": "User is Logged Out",
  "refreshProfile": "Refresh profile"
}
```

Add the same key to **every** locale file (`vi.arb`, …). The template file is whichever `l10n.yaml` names.

### Check the feature's `l10n.yaml`

```yaml
# modules/home/feature/l10n.yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureHomeLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

Each feature gets its **own** `output-class` (`FeatureHomeLocalizations`, `FeatureAuthLocalizations`, …) so delegates never collide.

### Generate the Dart code

```bash
cd modules/home/feature && flutter gen-l10n && cd -
```

`build_runner` does not touch ARB files; `gen-l10n` reads the package's `l10n.yaml`.
`dart tools/workspace_setup/configure.dart` runs it for every package that has one.
Missing translations are reported in `untranslated-messages.txt`.

### Register the delegate (once per feature)

```dart
// modules/home/feature/lib/di/localization.dart
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

### Expose a typed extension

```dart
// modules/home/feature/lib/src/extensions/l10n_home_extension.dart
extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

### Use the string

```dart
Text(context.l10nHome.userLoggedIn)
```

## 2. Add a locale

Adding a language touches `core_base_ui` **and every feature that ships strings** — not just the one you are working on. Japanese (`ja`) as the example.

### Add the ARB and the language's name to `core_base_ui`

Create `ja.arb` in `platform/ui/design_system/assets/language/` with `"@@locale": "ja"` and every key of the template `en.arb`. Then add the language's display name to **every** `core_base_ui` ARB — `en.arb` and `vi.arb` as well as `ja.arb` — next to `languageEn` / `languageVi`:

```json
{
  "@@locale": "en",
  "languageEn": "English",
  "languageVi": "Tiếng Việt",
  "languageJa": "Japanese"
}
```

`core_base_ui`'s `AppLocalizations.supportedLocales` is what the app offers: `MaterialApp.supportedLocales` (`platform/shell/app_shell/lib/src/app_material_wrapper.dart`), `LanguageProvider`'s stored-locale check and the Settings picker (`modules/settings/feature/lib/src/pages/settings_page.dart`) all read it. `gen-l10n` builds it from the ARB files present, so the new file is what adds the locale.

### Name the language in the picker

`platform/ui/design_system/lib/src/extensions/locale_extension.dart` maps a language code to that name; without a case the picker shows the bare tag `ja`:

```dart
return switch (languageCode) {
  'vi' => context.l10n.languageVi,
  'en' => context.l10n.languageEn,
  'ja' => context.l10n.languageJa,
  _ => toLanguageTag(),
};
```

### Add an ARB to every feature

Add `assets/language/ja.arb`, every key translated, to **each** feature with an `l10n.yaml` — today `modules/{auth,home,onboarding,settings,splash}/feature`. This is not optional: each feature's extension force-unwraps its delegate —

```dart
FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
```

— and a feature with no `ja.arb` has a delegate that does not support `ja`, so `of(this)` returns `null` and the first `context.l10nHome` after the user picks Japanese throws. `find modules -name l10n.yaml` lists them. A feature scaffolded later gets only `en.arb` / `vi.arb` from `tools/module_generator/templates/feature/localization/` — add the locale there too, or to each new feature by hand.

### Order the locales in `preferred-supported-locales`

`platform/ui/design_system/l10n.yaml` and each feature's `l10n.yaml` say `preferred-supported-locales: [en, vi]`, as does the generator's `l10n.yaml.mustache`. `gen-l10n` still picks up `ja.arb` without an edit — the list only **orders** the locales, and those it omits follow alphabetically — but the first supported locale is the fallback (`localeResolutionCallback` and `LanguageProvider` both fall back to `supportedLocales.first`). Append the new locale to keep the order explicit: `[en, vi, ja]`.

### Regenerate

```bash
dart tools/workspace_setup/configure.dart   # gen-l10n in every package with an l10n.yaml, then codegen + barrels
```

Or `flutter gen-l10n` in `platform/ui/design_system` and in each feature. Check every package's `untranslated-messages.txt` is empty.

## 3. Style a widget with design tokens

Tokens live in `platform/ui/design_system/lib/src/styles/`; colours come from a
`ThemeExtension` so they flip with light/dark automatically.

| Token class | File | Purpose |
|---|---|---|
| `AppSpacing` | `app_spacing.dart` | Paddings, margins, gaps |
| `AppRadius` | `app_radius.dart` | Corner radii, `BorderRadius` objects |
| `AppTextStyles` | `app_text_styles.dart` | Typography, resolved from theme |
| `AppGradients` | `app_gradients.dart` | Gradients, resolved from theme |
| `AppShadows` | `app_shadows.dart` | Elevation shadows |

Every accessor takes a `BuildContext`, because scaling resolves through the
context-aware extensions of `core_responsive`:

```dart
Container(
  color: context.colors.surface,
  padding: EdgeInsets.all(AppSpacing.lg(context)),
  child: Text(
    context.l10nHome.home,
    style: AppTextStyles.bodyMediumStyle(context),
  ),
)
```

> [!CAUTION]
> Never hard-code a `Color`, `fontSize`, spacing number or `BorderRadius` in a
> widget. If a token is missing, add it to `core_base_ui` — do not inline the
> value. And never re-scale an already-scaled token:
> `context.w(AppSpacing.lg(context))` scales twice.

> [!NOTE]
> **Configuring the design system — swapping the palette, changing the font,
> retuning the scales, moving the design canvas, adding a token — has its own
> page: [`11_design_system.md`](11_design_system.md).** It is kept separate so
> there is exactly one place describing how these values are defined.

## 4. Size every dimension through context

Every dimension is scaled, and always through a `BuildContext`:

| Extension | Use for |
|---|---|
| `context.w(x)` | Widths, horizontal padding/margin |
| `context.h(x)` | Heights, vertical gaps |
| `context.sp(x)` | Font sizes |
| `context.r(x)` | Border radii, square/circular sizes |

There is **no `num` extension**: `24.h` does not compile. A number carries no
context, so it could only read a global — and a widget reading a global never
learns the metrics changed. `arch_check` rule R7 rejects the bare form anyway.

```dart
// ❌ Wrong
SizedBox(height: 24)
padding: EdgeInsets.all(16)
fontSize: 16

// ✅ Right — context-aware extensions
SizedBox(height: context.h(24))
padding: EdgeInsets.all(context.w(16))
fontSize: context.sp(16)

// ✅ Better — use a token
SizedBox(height: AppSpacing.lgH(context))
padding: EdgeInsets.all(AppSpacing.lg(context))
```

> [!NOTE]
> `context.edgeInsets(all: 16)` scales with `w`, so it *is* a drop-in swap for
> `EdgeInsets.all(context.w(16))`. `horizontal:` scales with `w`, `vertical:`
> with `h`. See [`11_design_system.md`](11_design_system.md) for the full axis
> table.
>
> For a side that means start or end of the line, use
> `context.edgeInsetsDirectional(start:, end:)` — `left:`/`right:` are
> physical and do not flip in a right-to-left locale.

Values that are *not* physical sizes are exempt: `TextStyle.height` is a line-height multiplier, `flex` is a ratio.

By default nothing scales past the design size: a tablet or desktop window draws the design 1:1, and the room it adds is spent on layout, chosen by window size class. The scale policy and the adaptive widgets are in [`11_design_system.md`](11_design_system.md) §6–§7.

## 5. Scale a reusable widget's own constants, never its parameters

> [!CAUTION]
> A reusable widget in `core_ui_kit` **must not scale the parameters it receives**. The caller scales before passing, so a value arrives already in device pixels and has to be used as-is; scaling it again double-scales, and a caller passing a token cannot override it at all. A widget's **own** constants are the opposite case: it must scale those, or it is not responsive.

What the rule forbids — an `AppBar` in `core_ui_kit` that ends with:

```dart
// ❌ Forbidden: a hardcoded override in a reusable widget
@override
double? get leadingWidth => context.w(64);
```

That override scales internally **and** silently discards the `leadingWidth` the caller passed through `super.leadingWidth` — the parameter is dead. `AppBarCustom` instead forwards everything to `AppBar`:

```dart
// platform/ui/ui_kit/lib/navigation/app_bar_custom.dart
class AppBarCustom extends AppBar {
  AppBarCustom({
    super.key,
    super.leading,
    super.automaticallyImplyLeading = true,
    // ... every field forwarded, none overridden ...
  }) : assert(elevation == null || elevation >= 0.0);
}
```

Call sites scale:

```dart
AppBarCustom(leadingWidth: context.w(64), title: Text(context.l10nHome.home))
```

## 6. Keep a shared widget's defaults in its `utils/`

Non-size defaults for shared widgets live in the package's own `utils/`:

```dart
// platform/ui/ui_kit/lib/src/utils/shared_ui_constants.dart
/// Timing and overlay constants owned by `core_ui_kit`.
///
/// Package-internal by convention: these are defaults for the reusable
/// widgets in this package. Features that need a different value pass it
/// explicitly through the widget's constructor instead of reading these.
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

## 7. Extract dialogs and bottom sheets into classes

> [!CAUTION]
> Never build a dialog inline inside `showDialog()` / `showModalBottomSheet()`. Extract it into its own file and class.

| Kind | File suffix | Class suffix |
|---|---|---|
| Dialog | `_dialog.dart` | `Dialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` |

Existing examples in `platform/ui/ui_kit/lib/src/dialogs/`: `error_dialog.dart`, `warning_dialog.dart`, `retry_dialog.dart`, `bottom_wrapper_dialog.dart`.

Inline builders cannot be reused, previewed, or tested in isolation — and they invariably end up with hard-coded strings and sizes.

---

## Verify

```bash
cd modules/<name>/feature && flutter gen-l10n && cd -   # then check untranslated-messages.txt is empty
dart tools/unused_checker/check_unused_translate.dart   # no key left unused
dart tools/arch_check/check.dart                        # R7: no bare sizing extension (24.h)
flutter analyze                                         # No issues found!
cd modules/<name>/feature && flutter test               # page tests run under ResponsiveInit (RULE-62)
```

On a device, switch the language in Settings and toggle light/dark: every string and colour on your screen must follow. Run once on a phone and once in a wide window or split screen.

Review checklist:

- [ ] No hard-coded user-facing string anywhere
- [ ] New key added to **all** `.arb` locale files, `flutter gen-l10n` run
- [ ] New locale: an ARB in `core_base_ui` **and every feature**, its name in `locale_extension.dart` (step 2)
- [ ] Feature registers `IFeatureLocalization`; `root_app.dart` untouched
- [ ] `core_ui_kit` uses `core_base_ui` strings, defines no `.arb`
- [ ] Colours via `context.colors.*`, typography via `AppTextStyles.*(context)`
- [ ] Every dimension scaled through context (`context.w`/`context.h`/`context.sp`/`context.r`) or taken from a token
- [ ] Tokens not double-scaled (`AppSpacing.lg(context)`, not `context.w(AppSpacing.lg(context))`)
- [ ] Reusable widgets use parameters as received (the caller scaled them); they scale only their own constants
- [ ] Dialogs/bottom sheets extracted into their own suffixed files

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `context.l10nX.newKey` does not exist | `gen-l10n` has not run since the ARB edit | `cd modules/<name>/feature && flutter gen-l10n` (step 1) |
| `gen-l10n` fails on an ARB file | A `//` comment or a trailing comma — ARB is strict JSON | Remove it (step 1) |
| The app throws on the first `context.l10nX` after picking a new language | That feature has no ARB for the language, so its delegate returns `null` | Add the ARB to **every** feature (step 2) |
| The picker shows a bare tag such as `ja` | `locale_extension.dart` has no case for the code | Add the case (step 2) |
| A widget does not resize on rotation or split screen | A raw double, or a value computed outside `build` | Scale through `context` inside `build` (step 4) |
| `ResponsiveScope.of` asserts in a widget test | The widget under test is not wrapped in `ResponsiveInit` | Wrap it (RULE-62) |
| A size is twice what the design says | A value was scaled twice (`context.w(AppSpacing.lg(context))`) | Use the token as-is (steps 3 and 5) |
| A colour is wrong in dark mode | A hard-coded `Color` | Use `context.colors.*` (step 3) |

## Related

- Rules: RULE-30 (scale through context), RULE-31 (reusable widgets use parameters as received), RULE-33 (tokens only), RULE-34 (translate everything), RULE-35 (`lowerCamelCase` keys), RULE-36 (dialogs are classes), RULE-37 (feature assets stay in the feature), RULE-62 (`ResponsiveInit` in tests) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`11_design_system.md`](11_design_system.md) — configure the tokens, scale policy and adaptive layouts
- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` contains zero widgets
- [`../architecture/05_features.md`](../architecture/05_features.md) — feature package layout
- [`06_storage.md`](06_storage.md) — how theme and locale are persisted
