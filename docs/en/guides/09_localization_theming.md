# Guide: Localization, Theming & Responsive UI

**What this answers:** how a feature ships its own translations without touching the app shell, and how every colour, font and dimension stays consistent across light/dark and screen sizes.

**After reading you can:** add a translated string, add a locale, style a widget with design tokens, and size it responsively without breaking the reusable-widget contract.

---

# Part A — Localization

## 1. Decentralised by design

Each feature owns its translations. The app shell never learns their names.

| Where | What lives there |
|---|---|
| `packages/features/<f>/assets/language/*.arb` | The feature's translation files |
| `packages/features/<f>/l10n.yaml` | Codegen config for that feature |
| `packages/features/<f>/lib/src/gen/language/` | Generated delegate + classes |
| `packages/features/<f>/lib/di/localization.dart` | `IFeatureLocalization` implementation |
| `core_base_ui` | Global / fallback strings shared by everyone |

> [!CAUTION]
> A feature must **never** edit `app/lib/presentation/root_app.dart` or `app_material_wrapper.dart` to register its delegate. Registration happens through DI — see §3.

## 2. The contract

```dart
// packages/core/di/lib/src/feature_localization.dart
/// Interface for feature localization delegates.
/// Enables safe registration and retrieval via getIt.getAll<IFeatureLocalization>() in the root app.
abstract class IFeatureLocalization {
  LocalizationsDelegate get delegate;
}
```

## 3. How the shell collects delegates

```dart
// app/lib/presentation/app_material_wrapper.dart
// `getAllOrEmpty`, not `getIt.getAll`: the latter throws when no feature
// registers `IFeatureLocalization`. Every feature package is removable, so
// an app built without any of them must still resolve its delegates —
// falling back to the global `core_base_ui` ones.
final delegates = [
  ...getAllOrEmpty<IFeatureLocalization>().map((e) => e.delegate),
  ...AppLocalizations.localizationsDelegates,
];
```

`getAllOrEmpty` is what makes a feature removable: delete the package and the list simply gets shorter.

## 4. Add a translated string — step by step

### Step 1 — edit the `.arb` files

```json
// packages/features/home/assets/language/en.arb
{
  "@@locale": "en",
  "home": "Home",
  "tabLabel": "Home",
  "user_logged_in": "User is Logged In",
  "user_logged_out": "User is Logged Out",
  "refresh_profile": "Refresh profile"
}
```

Add the same key to **every** locale file (`vi.arb`, …). The template file is whichever `l10n.yaml` names.

### Step 2 — check the feature's `l10n.yaml`

```yaml
# packages/features/home/l10n.yaml
arb-dir: assets/language
template-arb-file: en.arb
output-localization-file: app_localizations.dart
output-class: FeatureHomeLocalizations
preferred-supported-locales: [en, vi]
untranslated-messages-file: untranslated-messages.txt
output-dir: lib/src/gen/language
```

Each feature gets its **own** `output-class` (`FeatureHomeLocalizations`, `FeatureAuthLocalizations`, …) so delegates never collide.

### Step 3 — generate

```bash
dart run build_runner build -d --workspace
```

Missing translations are reported in `untranslated-messages.txt`.

### Step 4 — register the delegate (once per feature)

```dart
// packages/features/home/lib/di/localization.dart
@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
```

### Step 5 — expose a typed extension

```dart
// packages/features/home/lib/src/extensions/l10n_home_extension.dart
extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
```

### Step 6 — use it

```dart
Text(context.l10nHome.user_logged_in)
```

## 5. Rules

- **No hard-coded user-facing strings.** Ever. Toasts, dialogs, error messages and button labels all go through a delegate.
- Feature-specific strings → that feature's `.arb`.
- Genuinely global strings → `core_base_ui`.
- `core_ui_kit` does **not** define its own `.arb` files. It is a widget library used by every feature; its strings come from `core_base_ui`.

---

# Part B — Theming

## 6. Design tokens and colours

Tokens live in `packages/core/base_ui/lib/src/styles/`; colours come from a
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

## 8. `ThemeMode.system` follows the OS live

`ThemeMode.system` resolves against OS brightness, which can change while the app is running. `ThemeProvider` observes it:

```dart
// packages/core/base_ui/lib/src/theme/theme_provider.dart
/// Called by the framework when the OS switches between Light and Dark.
///
/// Only [ThemeMode.system] derives its appearance from the platform, so an
/// explicit light/dark choice is left untouched — no wasted rebuild.
@override
void didChangePlatformBrightness() {
  super.didChangePlatformBrightness();
  if (_themeMode != ThemeMode.system) return;

  // Refresh the status/navigation bar styling for the new brightness…
  setSystemTheme();
  // …and rebuild consumers, because `currentTheme` now resolves differently.
  notifyListeners();
}
```

It uses `WidgetsBindingObserver` (a list) rather than assigning `platformDispatcher.onPlatformBrightnessChanged` (a single slot another library could overwrite). Cleanup is wired into DI:

```dart
@disposeMethod
@override
void dispose() {
  if (_isObservingPlatform) {
    WidgetsBinding.instance.removeObserver(this);
```

The persisted preference is read through `IThemeStorage` — see [`06_storage.md`](06_storage.md#8-crossing-a-package-boundary).

---

# Part C — Responsive UI

## 9. `core_responsive` is mandatory

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
padding: EdgeInsets.all(context.r(16))
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

Values that are *not* physical sizes are exempt: `TextStyle.height` is a line-height multiplier, `flex` is a ratio.

## 10. Reusable widgets take RAW values

> [!CAUTION]
> A reusable widget in `core_ui_kit` **must not scale its own parameters**. It accepts raw numbers; the caller scales before passing them in. Scaling inside means a caller who already scaled gets double-scaling, and a caller who passes a token cannot override it at all.

This rule exists because it was broken. `AppBarCustom` used to end with:

```dart
// ❌ The bug that motivated this rule (now removed)
@override
double? get leadingWidth => context.w(64);
```

That override scaled internally **and** silently discarded the `leadingWidth` the caller passed through `super.leadingWidth` — the parameter was dead. The class now simply forwards everything to `AppBar`:

```dart
// packages/core/ui_kit/lib/navigation/app_bar_custom.dart
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

## 11. `core_ui_kit` constants

Non-size defaults for shared widgets live in the package's own `utils/`:

```dart
// packages/core/ui_kit/lib/utils/shared_ui_constants.dart
/// Timing and overlay constants owned by `core_ui_kit`.
///
/// Package-internal by convention: these are defaults for the reusable
/// widgets in this package. Features that need a different value pass it
/// explicitly through the widget's constructor instead of reading these.
class SharedUiConstants {
  SharedUiConstants._();

  static const Duration DIALOG_TRANSITION_DURATION = Duration(milliseconds: 200);
  static const Duration TOAST_DURATION = Duration(seconds: 3);
  static const Duration MEDIA_ERROR_TOAST_DURATION = Duration(seconds: 2);
  static const Color DIALOG_BARRIER_COLOR = Color(0x80000000);
}
```

## 12. Dialogs and bottom sheets are classes, not closures

> [!CAUTION]
> Never build a dialog inline inside `showDialog()` / `showModalBottomSheet()`. Extract it into its own file and class.

| Kind | File suffix | Class suffix |
|---|---|---|
| Dialog | `_dialog.dart` | `Dialog` |
| Bottom sheet | `_bottom_sheet.dart` | `BottomSheet` |

Existing examples in `packages/core/ui_kit/lib/dialogs/`: `error_dialog.dart`, `warning_dialog.dart`, `retry_dialog.dart`, `bottom_wrapper_dialog.dart`.

Inline builders cannot be reused, previewed, or tested in isolation — and they invariably end up with hard-coded strings and sizes.

---

## 13. Checklist

- [ ] No hard-coded user-facing string anywhere
- [ ] New key added to **all** `.arb` locale files, `build_runner` run
- [ ] Feature registers `IFeatureLocalization`; `root_app.dart` untouched
- [ ] `core_ui_kit` uses `core_base_ui` strings, defines no `.arb`
- [ ] Colours via `context.colors.*`, typography via `AppTextStyles.*(context)`
- [ ] Every dimension scaled (`.w`/`.h`/`.sp`/`.r`) or taken from a token
- [ ] Tokens not double-scaled (`AppSpacing.lg(context)`, not `context.w(AppSpacing.lg(context))`)
- [ ] Reusable widgets accept raw values and scale nothing internally
- [ ] Dialogs/bottom sheets extracted into their own suffixed files

## See also

- [`../architecture/02_core.md`](../architecture/02_core.md) — `core_base_ui` contains zero widgets
- [`../architecture/05_features.md`](../architecture/05_features.md) — feature package layout
- [`06_storage.md`](06_storage.md) — how theme and locale are persisted
- [`../reference/01_rules.md`](../reference/01_rules.md) — the full rule list
