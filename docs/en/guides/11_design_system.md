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
| Where | [`lib/src/styles/`](../../../platform/base_ui/lib/src/styles/) | [`lib/src/theme/`](../../../platform/base_ui/lib/src/theme/) |
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

Open [`theme/theme_system_interface.dart`](../../../platform/base_ui/lib/src/theme/theme_system_interface.dart). It declares every colour slot the app can ask for:

```dart
// platform/base_ui/lib/src/theme/theme_system_interface.dart
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

Both palettes are plain static fields in [`theme/theme_system_extensions.dart`](../../../platform/base_ui/lib/src/theme/theme_system_extensions.dart):

```dart
// platform/base_ui/lib/src/theme/theme_system_extensions.dart
/// Light theme extension
static ThemeSystemExtension light = ThemeSystemExtension(
  primary: const Color(0xff0A7E8C),
  primaryContainer: const Color(0xff8B5CF6),
  background: const Color(0xffF8FAFC),
  surface: const Color(0xffFFFFFF),
  textPrimary: const Color(0xff0F172A),
  // …
);

/// Dark theme extension
static ThemeSystemExtension dark = ThemeSystemExtension(
  primary: const Color(0xff22D3EE),
  background: const Color(0xff0B0F19),
  surface: const Color(0xff151F32),
  textPrimary: const Color(0xffF8FAFC),
  // …
);
```

Change the hex values, save, hot-restart. **Always edit both** — a light-only change leaves dark mode on the sample palette.

One slot exists only for a sample screen: `liquidOnboardingColors`, the splash gradient (`AppGradients.liquidOnboarding`). Delete the splash sample and remove that slot from the interface, both palettes and `AppGradients` rather than leaving a dead colour behind.

### Step 3 — read them in a widget

```dart
// via the extension in platform/base_ui/lib/src/extensions/context_extension.dart
Container(
  color: context.colors.surface,
  child: Text('Hi', style: TextStyle(color: context.colors.textPrimary)),
)
```

> [!NOTE]
> `context.colors` and `context.primary` are **not** the same thing. `context.colors.*` reads your `ThemeSystemExtension`; the bare getters (`context.primary`, `context.surface`, …) read Material's own `ColorScheme`. Only two of those are wired to your palette — `ThemeProvider` copies `primary` and `surface` into the `ColorScheme`. Prefer `context.colors.*` for brand colours.

---

## 3. Change the typeface

Typography is built once per theme in [`theme/theme_provider.dart`](../../../platform/base_ui/lib/src/theme/theme_provider.dart), then scaled.

### Swap the font family

The template uses Google Fonts:

```dart
// platform/base_ui/lib/src/theme/theme_provider.dart
// The M3 type scale's sizes. `ThemeData().textTheme` carries colours only.
final geometry = Typography.material2021().englishLike;

TextTheme applyGoogleFont(TextTheme colors) {
  final font = GoogleFonts.plusJakartaSans();
  return geometry
      .merge(colors)
      .apply(
        fontFamily: font.fontFamily,
        fontFamilyFallback: font.fontFamilyFallback,
      );
}

final defaultTheme = switch (mode) {
  ThemeMode.dark => applyGoogleFont(ThemeData.dark().textTheme),
  ThemeMode.light => applyGoogleFont(ThemeData.light().textTheme),
  ThemeMode.system => applyGoogleFont(
    ThemeData.from(colorScheme: colorScheme).textTheme,
  ),
};
```

**Another Google font:** change the one line `GoogleFonts.plusJakartaSans()` inside `applyGoogleFont` to any `GoogleFonts.<name>()`; all three branches go through it.

**A bundled font:** declare it under `flutter: fonts:` in [`platform/base_ui/pubspec.yaml`](../../../platform/base_ui/pubspec.yaml), then make `applyGoogleFont` return `geometry.merge(colors).apply(fontFamily: 'YourFont')` — keep the `geometry.merge`, it is where the sizes come from. Drop the `google_fonts` dependency once nothing uses it — `dart tools/unused_checker/check_unused_packages.dart` reports it as declared-but-unused.

### How font scaling works

The sizes come from `Typography.material2021().englishLike` — the Material 3 type scale — because `ThemeData().textTheme` carries colours only (Material adds the sizes later, when `MaterialApp` localizes the theme; scaling the colour-only theme scaled nothing). Every size is then re-scaled through the context-aware extension, as is the app-bar title (`BaseUiConstants.APP_BAR_TITLE_FONT_SIZE`):

```dart
// platform/base_ui/lib/src/theme/theme_provider.dart
double? scaleFont(double? size) =>
    size == null ? null : context.spMin(size);
```

`spMin`, not `sp`: text shrinks on a screen narrower than the 375-wide design and never grows past the design size. `sp` scales by width, and every app shares this theme — on a 1280-wide desktop window it would triple every font. On a phone 375 or wider, text is simply the design size.

That is why `ThemeProvider.currentTheme`, `lightTheme` and `darkTheme` all take a `BuildContext` — they cannot scale without one. They are called from inside the `Consumer2` builder in `platform/app_shell/lib/presentation/app_material_wrapper.dart`, which has one.

`AppTextStyles` then just reads the finished theme:

```dart
// platform/base_ui/lib/src/styles/app_text_styles.dart
static TextStyle bodyMediumStyle(BuildContext context) =>
    context.bodyMediumStyle;
```

> [!CAUTION]
> Do not add `.sp` at the call site. Text styles are **already scaled** by the time `AppTextStyles` returns them. Writing `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: context.sp(14))` scales twice.

---

## 4. Change the spacing and radius scales

Both classes follow the same shape: a **context-taking accessor** for use in widgets, and a **`raw*` constant** that is the single source of the number.

```dart
// platform/base_ui/lib/src/styles/app_spacing.dart
static double lg(BuildContext context) => context.w(rawLg);
// …
static const double rawLg = 16;
```

To retune the scale, edit the `raw*` constant — every accessor derives from it, so you change one number, not two.

```dart
// platform/base_ui/lib/src/styles/app_radius.dart
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

`core_responsive` ships shorthands on the same `BuildContext` extension. Verified against `platform/responsive/lib/src/context_extension.dart`, they map to these axes:

```dart
context.edgeInsets(all: X)          // → EdgeInsets.all(w(X))
context.edgeInsets(horizontal: X)   // → left/right = w(X)
context.edgeInsets(vertical: X)     // → top/bottom = h(X)
context.edgeInsets(left: X)         // → w(X)      (same for right)
context.edgeInsets(top: X)          // → h(X)      (same for bottom)
context.borderRadius(all: X)        // → BorderRadius.circular(r(X))
context.verticalSpace(X)            // → SizedBox(height: h(X))
context.horizontalSpace(X)          // → SizedBox(width: w(X))
```

> [!NOTE]
> **`context.edgeInsets(all:)` scales with `w`**, so it is a true drop-in for `EdgeInsets.all(context.w(16))`. Each axis of `edgeInsets` is scaled by the axis it belongs to, which keeps padding proportional instead of tracking one dimension.
>
> `borderRadius` uses `r` — a radius scaled on one axis alone would turn a circle into an ellipse. When in doubt, write the explicit form, which states the axis out loud.

---

## 5. Change the design canvas size

Everything above scales *relative to a reference canvas*: the screen size your designer worked at.

```dart
// platform/common/lib/src/config/app_config.dart
/// Design size used for responsive UI calculations
/// Based on iPhone X dimensions (375x812)
static Size get design => const Size(375, 812);
```

It is handed to the package once, at the root of the tree:

```dart
// platform/app_shell/lib/main_scope.dart
return ResponsiveInit(
  designSize: AppConfig.design,
  splitScreenMode: true,
  child: child,
);
```

| Parameter | What it does |
|---|---|
| `designSize` | The reference canvas (`core_responsive` defaults to 360×690; this app passes `AppConfig.design`). `context.w(16)` means "16 logical pixels **on a 375-wide design**", rescaled to the real device. |
| `minTextAdapt` | Not set here (default `false`), so `sp` uses the **width** factor — text scales with the same ratio as horizontal spacing. `true` switches to the **smaller** of the width and height factors, which keeps text from ballooning on wide, short windows but shrinks it in landscape. |
| `fontSizeResolver` | Not set here. Overrides how `sp` is computed, **entirely** — while it is set, `minTextAdapt` is inert. Compute from the `metrics` it receives: they measure this window, so split-screen and resizing stay correct. |
| `splitScreenMode` | Floors the height used for scaling at `ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT` (700), keeping scaling sane when the app is a split-screen pane rather than full-screen. |

> [!CAUTION]
> **Changing `designSize` re-scales the entire app at once.** Every `context.w/h/r/sp` call resolves against it, so a UI tuned at 375×812 will not simply "look bigger" at 390×844 — proportions shift. Change it only when your design source of truth actually changed, then sweep the app on a small phone, a tall phone and a tablet.

`ResponsiveInit` sits at the very root (`_ResponsiveWrapper` in `main_scope.dart` wraps everything, including `AppMaterialWrapper`), so every widget context in the app can use the context-aware extensions.

> [!NOTE]
> Rebuilding needs no configuration. `ResponsiveInit` is a `StatelessWidget` that reads `MediaQuery.sizeOf(context)` — a size-only dependency — and publishes `ResponsiveMetrics` through the `ResponsiveScope` `InheritedWidget`. Every `context.w/h/r/sp` call registers a dependency on that scope, so Flutter rebuilds exactly the widgets that read a scaled value. This is why there is no `num` extension: `16.w` could only read a global, and a global cannot notify anyone. `arch_check` rule R7 enforces it.

> [!TIP]
> `ResponsiveScope.of(context)` asserts when no `ResponsiveInit` is above it, rather than silently returning unscaled values. A widget test that scales must wrap its subject in `ResponsiveInit`.

---

## 6. Add a new token class

Say you want `AppElevation`. Follow the shape the existing classes use — private constructor, `raw*` constants, context-taking accessors.

**Step 1** — create `platform/base_ui/lib/src/styles/app_elevation.dart`:

```dart
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';

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
dart tools/barrel_generator/generate.dart platform/base_ui/lib
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
// platform/base_ui/lib/src/styles/app_gradients.dart
static LinearGradient primaryGradient(BuildContext context) {
  final colors = Theme.of(context).extension<ThemeSystemExtension>()!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors.primaryGradientColors,
  );
}
```

To change a gradient, edit the colour **list** in the palette (`primaryGradientColors`, `liquidOnboardingColors`), not the widget.

`AppShadows` is the odd one out — it hard-codes black with an alpha and is **not** theme-aware:

```dart
// platform/base_ui/lib/src/styles/app_shadows.dart
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

Full list in [`../reference/01_rules.md`](../reference/01_rules.md). Which of these a machine holds is stated per rule, because it changes how much you can rely on review catching it.

- **Never hard-code** a `Color`, `fontSize`, spacing number or `BorderRadius` in a widget. Missing a token? Add it to `core_base_ui` — do not inline the value. *Review-held.* See the note below for why.
- **Every dimension scales.** A bare `SizedBox(height: 24)` is a bug; write `SizedBox(height: context.h(24))` or `context.verticalSpace(24)`. *`arch_check` R7 holds the bare-extension half (`24.h`); the raw-double half is review-held.*
- **A widget scales its own constants, never its parameters.** A `core_ui_kit` widget receives already-scaled values — the caller scaled them — so using a parameter raw is correct and `context.w(widget.width)` is a double-scale bug. Its *own* padding and radii it must scale, or it is not responsive. `custom_input_field.dart` shows both in one line: `widget.paddingBottom ?? context.h(10)`. *Review-held.*
- **Do not scale an already-scaled value.** `AppSpacing.lg(context)` is final; `context.w(AppSpacing.lg(context))` is a double-scale bug. Likewise `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: ...)` — `ThemeProvider` already scaled every step, so overriding the size discards the scale and pins a number the design system cannot change. Reach for a different step instead. *Review-held.*
- **Edit `raw*`, not the accessor**, when retuning a scale.

> [!NOTE]
> **Why the colour and font-size rules are not machine-checked.**
>
> They were considered and deliberately left to review. A check for `Colors.<name>` would have to allow the places a literal colour is *correct* — `AppShadows`, which is the token file, and every modal scrim, where Flutter's own `ModalBarrier` is a fixed black and a theme-aware value would *lighten* the screen in dark mode. On this tree that is seven approved uses against two real ones, and a rule whose exception list outweighs its findings teaches people to skim it.
>
> The repo also forbids suppression comments, so there is no honest escape hatch for the legitimate cases. Review it is — which is exactly why three dark-mode bugs survived in `core_ui_kit` until they were audited for, and worth knowing when you copy a widget out of it.

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
| The design canvas | `platform/common/lib/src/config/app_config.dart` → `design` |
| Scaling behaviour (`minTextAdapt`, `fontSizeResolver` — neither set today) | `platform/app_shell/lib/main_scope.dart` → `ResponsiveInit` |
| Add a whole new token class | new file in `styles/`, then run the barrel generator |

---

## See also

- [`09_localization_theming.md`](09_localization_theming.md) — using tokens in widget code, and per-feature translations
- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_base_ui` sits, and why it ships zero widgets
- [`../reference/01_rules.md`](../reference/01_rules.md) — the enforced rules, with the commands that verify them
