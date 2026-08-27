# Guide: Configuring the design system

**This page answers:** where every colour, font, spacing step and corner radius is defined, and exactly which file to edit to make the template look like *your* product instead of the sample.

**After reading you can:** swap the brand palette, change the typeface, retune the spacing and radius scales, move the design canvas size, and add a brand-new token that reaches widgets through `context`.

This is the **configuration** guide. For the rules about *using* tokens in day-to-day widget code — no hard-coded colours, reusable widgets take raw values — see [`09_localization_theming.md`](09_localization_theming.md).

---

## 1. The map: tokens vs theme

Two different things live in `core_base_ui`, and mixing them up is the most common source of confusion.

| | **Tokens** | **Theme** |
|---|---|---|
| What | The raw design values | The wiring that hands those values to Material |
| Where | [`lib/src/styles/`](../../../packages/core/base_ui/lib/src/styles/) | [`lib/src/theme/`](../../../packages/core/base_ui/lib/src/theme/) |
| Reached by | `AppSpacing.lg(context)` | `context.colors.surface`, `Theme.of(context)` |
| Change it to… | resize a gap, add a shadow | recolour the brand, change the font |

| Class | File | Owns |
|---|---|---|
| `AppSpacing` | `styles/app_spacing.dart` | padding / margin / gap scale |
| `AppRadius` | `styles/app_radius.dart` | corner radii, plus ready-made `BorderRadius` |
| `AppTextStyles` | `styles/app_text_styles.dart` | typography, resolved from the active theme |
| `AppGradients` | `styles/app_gradients.dart` | gradients, resolved from the active theme |
| `AppShadows` | `styles/app_shadows.dart` | elevation shadows (not theme-aware — see §7) |
| `ThemeSystemInterface` | `theme/theme_system_interface.dart` | the **contract**: which colour slots exist |
| `ThemeSystemExtension` | `theme/theme_system_extensions.dart` | the **values**: light and dark palettes |
| `ThemeProvider` | `theme/theme_provider.dart` | builds `ThemeData`, owns light/dark switching |
| `ContextExtension` | `extensions/context_extension.dart` | the `context.colors` / `context.bodyMediumStyle` accessors |

> [!NOTE]
> **Tokens are the approved exception to the "constants live in `utils/`" rule.** They stay in `styles/` because they are the design system's *public API*, imported directly by every feature, and because `styles/` describes them far better than the catch-all `utils/`. Do not "fix" this in a future cleanup — see [`../reference/01_rules.md`](../reference/01_rules.md).

---

## 2. Change the brand palette

Colours are delivered as a Flutter [`ThemeExtension`](https://api.flutter.dev/flutter/material/ThemeExtension-class.html), which is why they flip with light/dark automatically and animate between them.

### Step 1 — decide whether you need a new slot

Open [`theme/theme_system_interface.dart`](../../../packages/core/base_ui/lib/src/theme/theme_system_interface.dart). It declares every colour slot the app can ask for:

```dart
// packages/core/base_ui/lib/src/theme/theme_system_interface.dart
abstract class ThemeSystemInterface<T extends ThemeExtension<T>>
    extends ThemeExtension<T> {
  // Core colors
  final Color primary;
  final Color primaryContainer;
  final Color secondary;
  final Color secondaryContainer;

  // Backgrounds & Surfaces
  final Color background;
  final Color surface;
  final Color surfaceVariant;

  // Texts
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color textInverse;
  // …
}
```

**Only re-colouring?** Skip to Step 2 — the slots already exist.

**Adding a slot** (say `brandAccent`)? You must touch three places, in this order:

1. `theme_system_interface.dart` — add the `final Color brandAccent;` field and its `required this.brandAccent` constructor entry.
2. `theme_system_extensions.dart` — add `required super.brandAccent` to the constructor, a `brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!` line inside `lerp`, and a value in **both** `light` and `dark`.
3. Nothing else. `context.colors.brandAccent` works immediately, because `context.colors` returns the extension object itself.

> [!WARNING]
> Forgetting the `lerp` entry compiles fine but breaks theme *animation* — the new colour will snap instead of fading when the user toggles light/dark.

### Step 2 — edit the values

Both palettes are plain static fields in [`theme/theme_system_extensions.dart`](../../../packages/core/base_ui/lib/src/theme/theme_system_extensions.dart):

```dart
// packages/core/base_ui/lib/src/theme/theme_system_extensions.dart
/// Light theme extension
static ThemeSystemExtension light = ThemeSystemExtension(
  primary: const Color(0xff0A7E8C),          // Customer teal accent
  primaryContainer: const Color(0xff8B5CF6), // Owner violet accent
  background: const Color(0xffF8FAFC),
  surface: const Color(0xffFFFFFF),
  textPrimary: const Color(0xff0F172A),
  // …
);

/// Dark theme extension
static ThemeSystemExtension dark = ThemeSystemExtension(
  primary: const Color(0xff22D3EE),          // Customer dark cyan accent
  background: const Color(0xff0B0F19),
  surface: const Color(0xff151F32),
  textPrimary: const Color(0xffF8FAFC),
  // …
);
```

Change the hex values, save, hot-restart. **Always edit both** — a light-only change leaves dark mode on the sample palette.

The colour names shipped with the template (`chatMe`, `liquidOnboardingColors`, `liquidCustomerColors`, `liquidOwnerColors`, `liquidAuthColors`) come from the sample screens. If your product has no chat and no "liquid" gradients, delete those slots from the interface and both palettes rather than leaving dead colours behind.

### Step 3 — read them in a widget

```dart
// via the extension in packages/core/base_ui/lib/src/extensions/context_extension.dart
Container(
  color: context.colors.surface,
  child: Text('Hi', style: TextStyle(color: context.colors.textPrimary)),
)
```

> [!NOTE]
> `context.colors` and `context.primary` are **not** the same thing. `context.colors.*` reads your `ThemeSystemExtension`; the bare getters (`context.primary`, `context.surface`, …) read Material's own `ColorScheme`. Only two of those are wired to your palette — `ThemeProvider` copies `primary` and `surface` into the `ColorScheme`. Prefer `context.colors.*` for brand colours.

---

## 3. Change the typeface

Typography is built once per theme in [`theme/theme_provider.dart`](../../../packages/core/base_ui/lib/src/theme/theme_provider.dart), then scaled.

### Swap the font family

The template uses Google Fonts:

```dart
// packages/core/base_ui/lib/src/theme/theme_provider.dart
final defaultTheme = switch (mode) {
  ThemeMode.dark => GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.dark().textTheme,
  ),
  ThemeMode.light => GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.light().textTheme,
  ),
  // …
};
```

**Another Google font:** replace `plusJakartaSansTextTheme` with any `GoogleFonts.<name>TextTheme` in all branches.

**A bundled font:** declare it under `flutter: fonts:` in [`packages/core/base_ui/pubspec.yaml`](../../../packages/core/base_ui/pubspec.yaml), then swap the call for `ThemeData.light().textTheme.apply(fontFamily: 'YourFont')`. Drop the `google_fonts` dependency once nothing uses it — `dart tools/arch_check/check.dart` will flag it as declared-but-unused.

### How font scaling works

Every size in the `TextTheme` is re-scaled through the context-aware extension:

```dart
// packages/core/base_ui/lib/src/theme/theme_provider.dart
double? scaleFont(double? size) => size == null ? null : context.sp(size);
```

That is why `ThemeProvider.currentTheme`, `lightTheme` and `darkTheme` all take a `BuildContext` — they cannot scale without one. They are called from inside the `Consumer2` builder in `app/lib/presentation/app_material_wrapper.dart`, which has one.

`AppTextStyles` then just reads the finished theme:

```dart
// packages/core/base_ui/lib/src/styles/app_text_styles.dart
static TextStyle bodyMediumStyle(BuildContext context) =>
    context.bodyMediumStyle;
```

> [!CAUTION]
> Do not add `.sp` at the call site. Text styles are **already scaled** by the time `AppTextStyles` returns them. Writing `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: 14.sp)` scales twice.

---

## 4. Change the spacing and radius scales

Both classes follow the same shape: a **context-taking accessor** for use in widgets, and a **`raw*` constant** that is the single source of the number.

```dart
// packages/core/base_ui/lib/src/styles/app_spacing.dart
static double lg(BuildContext context) => context.w(rawLg);
// …
static const double rawLg = 16;
```

To retune the scale, edit the `raw*` constant — every accessor derives from it, so you change one number, not two.

```dart
// packages/core/base_ui/lib/src/styles/app_radius.dart
static double md(BuildContext context) => context.r(rawMd);

static BorderRadius mdRadius(BuildContext context) =>
    BorderRadius.all(Radius.circular(md(context)));

static const double rawMd = 8;
```

**Naming convention.** `xxs → xs → sm → md → lg → xl → xxl → xxxl → huge` for spacing; `xs → … → xxl` plus `circular` for radius. `AppSpacing` additionally exposes an `H` variant of every step (`lgH`, `xlH`, …) that scales on the **height** axis.

### Which axis: `w`, `h` or `r`?

| Extension | Scales against | Use for |
|---|---|---|
| `context.w(x)` | screen **width** | padding, margins, horizontal gaps, widths |
| `context.h(x)` | screen **height** | vertical gaps, fixed heights |
| `context.r(x)` | **min** of the width and height factors | corner radii, circles, anything that must stay round |
| `context.sp(x)` | font scaling | font sizes only |
| `context.spMin(x)` | font scaling, capped at the raw value | fonts that must never grow on large screens |

`r` uses the smaller of the two factors on purpose — scaling a radius on one axis alone would turn a circle into an ellipse on a tall or wide device.

Default to `w` for spacing. Reach for `h` only when the value is genuinely vertical *and* should shrink on short screens; overusing `h` makes layouts feel cramped in landscape.

### The convenience helpers — and one trap

`flutter_screenutil_plus` ships shorthands. Verified against the package source (`lib/src/extensions/responsive_size_context.dart` in 1.6.0), they map to these axes:

```dart
context.edgeInsets(all: X)          // → EdgeInsets.all(r(X))          ← .r !
context.edgeInsets(horizontal: X)   // → left/right = w(X)
context.edgeInsets(vertical: X)     // → top/bottom = h(X)
context.edgeInsets(left: X)         // → w(X)      (same for right)
context.edgeInsets(top: X)          // → h(X)      (same for bottom)
context.borderRadius(all: X)        // → BorderRadius.circular(r(X))
context.verticalSpace(X)            // → SizedBox(height: h(X))
context.horizontalSpace(X)          // → SizedBox(width: w(X))
```

> [!WARNING]
> **`context.edgeInsets(all:)` scales with `r`, not `w`.** So `EdgeInsets.all(16.w)` is **not** equivalent to `context.edgeInsets(all: 16)` — swapping one for the other shifts your layout on any device whose aspect ratio differs from the design canvas. The substitution is only safe when the original used `.r`.
>
> When in doubt, write the explicit form — `EdgeInsets.all(context.w(16))` — which always states the axis out loud.

---

## 5. Change the design canvas size

Everything above scales *relative to a reference canvas*: the screen size your designer worked at.

```dart
// packages/core/common/lib/src/config/app_config.dart
/// Design size used for responsive UI calculations
/// Based on iPhone X dimensions (375x812)
static Size get design => const Size(375, 812);
```

It is handed to the package once, at the root of the tree:

```dart
// app/lib/main_scope.dart
return ScreenUtilPlusInit(
  designSize: AppConfig.design,
  minTextAdapt: true,
  fontSizeResolver: (fontSize, instance) {
    final display = View.of(context).display;
    final screenSize = display.size / display.devicePixelRatio;
    final scaleWidth = screenSize.width / AppConfig.design.width;

    return fontSize * scaleWidth;
  },
  splitScreenMode: true,
  child: child,
);
```

| Parameter | What it does |
|---|---|
| `designSize` | The reference canvas. `context.w(16)` means "16 logical pixels **on a 375-wide design**", rescaled to the real device. |
| `minTextAdapt` | Lets text shrink as well as grow, so long strings do not overflow on small screens. |
| `fontSizeResolver` | Overrides how `sp` is computed. This template resolves fonts purely against **width ratio**, so text scales with the same factor as horizontal spacing rather than drifting on tall screens. |
| `splitScreenMode` | Keeps scaling sane when the app is a split-screen pane rather than full-screen. |

> [!CAUTION]
> **Changing `designSize` re-scales the entire app at once.** Every `context.w/h/r/sp` call resolves against it, so a UI tuned at 375×812 will not simply "look bigger" at 390×844 — proportions shift. Change it only when your design source of truth actually changed, then sweep the app on a small phone, a tall phone and a tablet.

`ScreenUtilPlusInit` sits at the very root (`_ResponsiveWrapper` in `main_scope.dart` wraps everything, including `AppMaterialWrapper`), so every widget context in the app can use the context-aware extensions.

> [!NOTE]
> The template keeps `autoRebuild` at its default (`true`). The package also offers `autoRebuild: false` as a performance option, but it only rebuilds widgets that use context-aware extensions — any remaining `16.w`-style call would silently stop responding to size changes. Leave it alone unless you have audited every call site.

---

## 6. Add a new token class

Say you want `AppElevation`. Follow the shape the existing classes use — private constructor, `raw*` constants, context-taking accessors.

**Step 1** — create `packages/core/base_ui/lib/src/styles/app_elevation.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil_plus/flutter_screenutil_plus.dart';

/// Elevation scale, resolved through the context-aware extensions.
class AppElevation {
  AppElevation._();

  static double flat(BuildContext context) => context.r(rawFlat);
  static double raised(BuildContext context) => context.r(rawRaised);

  /// Design values, unscaled. Single source of the numbers above.
  static const double rawFlat = 0;
  static const double rawRaised = 4;
}
```

**Step 2** — regenerate the barrel so it is exported:

```bash
dart tools/barrel_generator/generate.dart packages/core/base_ui/lib
```

`styles/styles.dart` is auto-generated — never hand-edit it; the generator strips manual `export` lines on the next run.

**Step 3** — use it. `core_base_ui`'s public barrel already re-exports `styles/`, so any feature gets it for free:

```dart
Material(elevation: AppElevation.raised(context), child: …)
```

---

## 7. Gradients and shadows

`AppGradients` reads live theme colours, so gradients recolour with the palette automatically:

```dart
// packages/core/base_ui/lib/src/styles/app_gradients.dart
static LinearGradient primaryGradient(BuildContext context) {
  final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors.primaryGradientColors,
  );
}
```

To change a gradient, edit the colour **list** in the palette (`primaryGradientColors`, `liquidOnboardingColors`, …), not the widget.

`AppShadows` is the odd one out — it hard-codes black with an alpha and is **not** theme-aware:

```dart
// packages/core/base_ui/lib/src/styles/app_shadows.dart
static List<BoxShadow> get sm => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.05),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
];
```

> [!NOTE]
> On a dark palette, a black shadow is nearly invisible. If your product leans on elevation in dark mode, promote the shadow colour into `ThemeSystemInterface` (§2, Step 1) and make these getters take a `BuildContext` like the other token classes. The template leaves it simple on purpose.

---

## 8. The rules that stay

These are enforced in review, and partly by `dart tools/arch_check/check.dart`. Full list in [`../reference/01_rules.md`](../reference/01_rules.md).

- **Never hard-code** a `Color`, `fontSize`, spacing number or `BorderRadius` in a widget. Missing a token? Add it to `core_base_ui` — do not inline the value.
- **Every dimension scales.** A bare `SizedBox(height: 24)` is a bug; write `SizedBox(height: context.h(24))` or `context.verticalSpace(24)`.
- **Reusable widgets in `core_ui_kit` take RAW values and never scale internally.** The caller scales before passing. A widget that scales a constructor argument scales it twice for any caller who already did. See [`09_localization_theming.md`](09_localization_theming.md).
- **Do not scale an already-scaled value.** `AppSpacing.lg(context)` is final; `AppSpacing.lg(context).w` is a double-scale bug.
- **Edit `raw*`, not the accessor**, when retuning a scale.

---

## 9. Quick lookup

| I want to change… | Edit |
|---|---|
| A brand colour | `theme/theme_system_extensions.dart` → `light` **and** `dark` |
| Add a colour slot | `theme/theme_system_interface.dart`, then both palettes + `lerp` |
| The typeface | `theme/theme_provider.dart` → `GoogleFonts.*TextTheme` |
| A font size in the ramp | `theme/theme_provider.dart` → the `copyWith` block |
| A spacing step | `styles/app_spacing.dart` → the `raw*` constant |
| A corner radius | `styles/app_radius.dart` → the `raw*` constant |
| A gradient | the colour list in `theme/theme_system_extensions.dart` |
| A shadow | `styles/app_shadows.dart` |
| The design canvas | `packages/core/common/lib/src/config/app_config.dart` → `design` |
| Scaling behaviour (`minTextAdapt`, `fontSizeResolver`) | `app/lib/main_scope.dart` → `ScreenUtilPlusInit` |
| Add a whole new token class | new file in `styles/`, then run the barrel generator |

---

## See also

- [`09_localization_theming.md`](09_localization_theming.md) — using tokens in widget code, and per-feature translations
- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_base_ui` sits, and why it ships zero widgets
- [`../reference/01_rules.md`](../reference/01_rules.md) — the enforced rules, with the commands that verify them
