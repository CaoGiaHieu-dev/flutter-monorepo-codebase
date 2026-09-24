# Guide: Configuring the design system

**This page answers:** where every colour, font, spacing step and corner radius is defined, exactly which file to edit to make the template look like *your* product instead of the sample, and how the UI scales and adapts from a phone to a tablet, a foldable or a desktop window.

**After reading you can:** swap the brand palette, change the typeface, retune the spacing and radius scales, move the design canvas size, decide how far each window class may scale, lay a screen out for tablets, foldables and split screen, and add a brand-new token that reaches widgets through `context`.

This is the **configuration** guide. For the rules about *using* tokens in day-to-day widget code — no hard-coded colours, reusable widgets take raw values — see [`09_localization_theming.md`](09_localization_theming.md).

---

## 1. The map: tokens vs theme

Two different things live in `core_base_ui`, and mixing them up is the most common source of confusion.

| | **Tokens** | **Theme** |
|---|---|---|
| What | The raw design values | The wiring that hands those values to Material |
| Where | [`lib/src/styles/`](../../../platform/ui/design_system/lib/src/styles/) | [`lib/src/theme/`](../../../platform/ui/design_system/lib/src/theme/) |
| Reached by | `AppSpacing.lg(context)` | `context.colors.surface`, `Theme.of(context)` |
| Change it to… | resize a gap, add a shadow | recolour the brand, change the font |

| Class | File | Owns |
|---|---|---|
| `AppSpacing` | `styles/app_spacing.dart` | padding / margin / gap scale |
| `AppRadius` | `styles/app_radius.dart` | corner radii, plus ready-made `BorderRadius` |
| `AppTextStyles` | `styles/app_text_styles.dart` | typography, resolved from the active theme |
| `AppGradients` | `styles/app_gradients.dart` | gradients, resolved from the active theme |
| `AppShadows` | `styles/app_shadows.dart` | elevation shadows (not theme-aware — see §9) |
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

Open [`theme/theme_system_interface.dart`](../../../platform/ui/design_system/lib/src/theme/theme_system_interface.dart). It declares every colour slot the app can ask for:

```dart
// platform/ui/design_system/lib/src/theme/theme_system_interface.dart
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

Both palettes are plain static fields in [`theme/theme_system_extensions.dart`](../../../platform/ui/design_system/lib/src/theme/theme_system_extensions.dart):

```dart
// platform/ui/design_system/lib/src/theme/theme_system_extensions.dart
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
// via the extension in platform/ui/design_system/lib/src/extensions/context_extension.dart
Container(
  color: context.colors.surface,
  child: Text(
    context.l10nHome.home, // a feature's localized getter — never a literal
    style: TextStyle(color: context.colors.textPrimary),
  ),
)
```

> [!NOTE]
> `context.colors` and `context.primary` are **not** the same thing. `context.colors.*` reads your `ThemeSystemExtension`; the bare getters (`context.primary`, `context.surface`, …) read Material's own `ColorScheme`. Only two of those are wired to your palette — `ThemeProvider` copies `primary` and `surface` into the `ColorScheme`. Prefer `context.colors.*` for brand colours.

---

## 3. Change the typeface

Typography is built once per theme in [`theme/theme_provider.dart`](../../../platform/ui/design_system/lib/src/theme/theme_provider.dart), then scaled.

### Swap the font family

The typeface — Plus Jakarta Sans — is **bundled** in `core_base_ui`, one file per weight under a single family:

```yaml
# platform/ui/design_system/pubspec.yaml
  fonts:
    - family: PlusJakartaSans
      fonts:
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Regular.ttf
          weight: 400
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Medium.ttf
          weight: 500
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/plus_jakarta_sans/PlusJakartaSans-Bold.ttf
          weight: 700
```

The theme applies that family to the whole type scale. `FontFamily.plusJakartaSans` is generated by `flutter_gen` (`lib/src/gen/fonts.gen.dart`) as `packages/core_base_ui/PlusJakartaSans` — a font declared by a package resolves only under that name:

```dart
// platform/ui/design_system/lib/src/theme/theme_provider.dart
// The type scale's sizes. A Material 3 `ThemeData().textTheme` carries
// colours only — its sizes are merged in later, when MaterialApp
// …
final geometry = Typography.material2021().englishLike;

// …
TextTheme applyFont(TextTheme colors) =>
    geometry.merge(colors).apply(fontFamily: FontFamily.plusJakartaSans);

final defaultTheme = switch (mode) {
  ThemeMode.dark => applyFont(ThemeData.dark().textTheme),
  ThemeMode.light => applyFont(ThemeData.light().textTheme),
  ThemeMode.system => applyFont(
    ThemeData.from(colorScheme: colorScheme).textTheme,
  ),
};
```

**Why bundled, not `google_fonts`.** `google_fonts` registers one family *per weight*, so a style whose weight changes later — `copyWith(fontWeight: FontWeight.bold)`, which the app-bar title and the samples do — keeps the regular file and the engine fakes the bold. One family with a file per weight lets Flutter pick the real face for any `fontWeight`. It also works offline and downloads nothing at runtime. The licence travels with the files: `assets/fonts/plus_jakarta_sans/OFL.txt`, registered with `LicenseRegistry` by `registerBaseUiLicenses()` (called in `runShellApp`), so it appears on `showLicensePage`.

**Another font:** put its files under `platform/ui/design_system/assets/fonts/<name>/` with its licence, list each weight under `flutter: fonts:` (a weight the design uses but you do not ship is synthesised from the nearest one), run `dart run build_runner build --workspace` so `FontFamily` gains the new constant, and point `applyFont` at it — keep the `geometry.merge`, it is where the sizes come from. Update the licence registration to the new licence file.

### How font scaling works

The sizes come from `Typography.material2021().englishLike` — the Material 3 type scale — because `ThemeData().textTheme` carries colours only (Material adds the sizes later, when `MaterialApp` localizes the theme; scaling the colour-only theme scaled nothing). Every size is then re-scaled through the context-aware extension, as is the app-bar title (`BaseUiConstants.APP_BAR_TITLE_FONT_SIZE`):

```dart
// platform/ui/design_system/lib/src/theme/theme_provider.dart
double? scaleFont(double? size) => size == null ? null : context.sp(size);
```

`sp`, so type follows the app's `textScaleBounds` ([§6](#6-scale-policy-down-by-default-up-on-opt-in-per-window-class)). With the default, `ScaleBounds.downOnly()`, text shrinks on a window narrower than the 375-wide design and never grows past the design size; a window class whose `ResponsiveProfile` opts into growth gets bigger type too. With this app's configuration, text is the design size on every window 375 wide or more — phone, tablet or desktop.

That is why `ThemeProvider.currentTheme`, `lightTheme` and `darkTheme` all take a `BuildContext` — they cannot scale without one. They are called from inside the `Consumer2` builder in `platform/shell/app_shell/lib/presentation/app_material_wrapper.dart`, which has one.

`AppTextStyles` then just reads the finished theme:

```dart
// platform/ui/design_system/lib/src/styles/app_text_styles.dart
static TextStyle bodyMediumStyle(BuildContext context) =>
    context.bodyMediumStyle;
```

> [!CAUTION]
> Do not add `.sp` at the call site. Text styles are **already scaled** by the time `AppTextStyles` returns them. Writing `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: context.sp(14))` scales twice.

### The user's font size is a second, separate factor

`context.sp` fits the design to the **window**; it never reads `MediaQuery.textScaler`. The **user's** OS font size is applied on top by `Text` itself, at layout, and the app shell passes it through up to 2x (`AppShellUiConstants.MAX_TEXT_SCALE_FACTOR`, applied by `AppMaterialWrapper` with `MediaQuery.withClampedTextScaling`). Two independent factors, each applied once — not a double scale. Do not cancel it with `MediaQuery.withNoTextScaling` or a `textScaler: TextScaler.noScaling` on a style: that fails WCAG's 200% text resize. What the text scale does *not* grow is a box sized with `context.h`/`context.w`, so give text containers padding or a `minHeight` rather than a fixed height. Details: [`06_app_shell.md`](../architecture/06_app_shell.md#the-os-font-size-is-honoured-up-to-2x).

---

## 4. Change the spacing and radius scales

Both classes follow the same shape: a **context-taking accessor** for use in widgets, and a **`raw*` constant** that is the single source of the number.

```dart
// platform/ui/design_system/lib/src/styles/app_spacing.dart
static double lg(BuildContext context) => context.w(rawLg);
// …
static const double rawLg = 16;
```

To retune the scale, edit the `raw*` constant — every accessor derives from it, so you change one number, not two.

```dart
// platform/ui/design_system/lib/src/styles/app_radius.dart
static double md(BuildContext context) => context.r(rawMd);

static BorderRadius mdRadius(BuildContext context) =>
    BorderRadius.all(Radius.circular(md(context)));

static const double rawMd = 8;
```

**Naming convention.** `xxs → xs → sm → md → lg → xl → xxl → xxxl → huge` for spacing; `xs → … → xxl` plus `circular` for radius. `AppSpacing` additionally exposes an `H` variant of every step (`lgH`, `xlH`, …) that scales on the **height** axis.

### Which axis: `w`, `h` or `r`?

| Extension | Scales against | Use for |
|---|---|---|
| `context.w(x)` | window **width** ratio, clamped by `scaleBounds` | padding, margins, horizontal gaps, widths |
| `context.h(x)` | window **height** ratio, clamped by `scaleBounds` | vertical gaps, fixed heights |
| `context.r(x)` | **min** of the width and height factors | corner radii, circles, anything that must stay round |
| `context.sp(x)` | text ratio, clamped by `textScaleBounds` | font sizes only |
| `context.spMin(x)` | `sp`, capped at the design value | text that must stay at the design size even where a profile (or a `fontSizeResolver`) lets text grow — under the default bounds it equals `sp` |

`r` uses the smaller of the two factors on purpose — scaling a radius on one axis alone would turn a circle into an ellipse on a tall or wide device.

Default to `w` for spacing. Reach for `h` only when the value is genuinely vertical *and* should shrink on short screens; overusing `h` makes layouts feel cramped in landscape.

### The convenience helpers — and one trap

`core_responsive` ships shorthands on the same `BuildContext` extension. Verified against `platform/ui/responsive/lib/src/context_extension.dart`, they map to these axes:

```dart
context.edgeInsets(all: X)          // → EdgeInsets.all(w(X))
context.edgeInsets(horizontal: X)   // → left/right = w(X)
context.edgeInsets(vertical: X)     // → top/bottom = h(X)
context.edgeInsets(left: X)         // → w(X)      (same for right) — physical side
context.edgeInsets(top: X)          // → h(X)      (same for bottom)
context.edgeInsetsDirectional(start: X)  // → EdgeInsetsDirectional, start = w(X) (same for end)
context.edgeInsetsDirectional(all: X / horizontal: X / vertical: X / top: X)  // same axes as edgeInsets
context.borderRadius(all: X)        // → BorderRadius.circular(r(X))
context.verticalSpace(X)            // → SizedBox(height: h(X))
context.horizontalSpace(X)          // → SizedBox(width: w(X))
```

> [!NOTE]
> **`context.edgeInsets(all:)` scales with `w`**, so it is a true drop-in for `EdgeInsets.all(context.w(16))`. Each axis of `edgeInsets` is scaled by the axis it belongs to, which keeps padding proportional instead of tracking one dimension.
>
> `borderRadius` uses `r` — a radius scaled on one axis alone would turn a circle into an ellipse. When in doubt, write the explicit form, which states the axis out loud.

> [!IMPORTANT]
> **`left`/`right` are physical; `start`/`end` follow the text direction.** `context.edgeInsets(left: 16)` stays on the left in Arabic or Hebrew. When the side means "where the line begins" — an indent before a label, the gap after a leading icon — use `context.edgeInsetsDirectional(start: 16)`, which returns an `EdgeInsetsDirectional` resolved against the ambient `Directionality`. A side argument wins over its axis, as in `edgeInsets`: `edgeInsetsDirectional(horizontal: 16, start: 24)` is 24 at the start and 16 at the end. Keep `edgeInsets(left:)` for sides that really are physical (a shadow offset, a hinge). The same goes for alignment: prefer `AlignmentDirectional.centerStart` to `Alignment.centerLeft`.

---

## 5. Change the design canvas size

Everything above scales *relative to a reference canvas*: the screen size your designer worked at.

```dart
// platform/foundation/common/lib/src/config/app_config.dart
/// Design size used for responsive UI calculations
/// Based on iPhone X dimensions (375x812)
static Size get design => const Size(375, 812);
```

It is handed to `ResponsiveInit` once, at the very root of the tree — `_ResponsiveWrapper` in `platform/shell/app_shell/lib/main_scope.dart` wraps everything, including `AppMaterialWrapper`; the full call is in §6. It is the artboard **every window class** measures against unless a profile names its own: `context.w(16)` means "16 logical pixels on the 375-wide design".

> [!CAUTION]
> **Changing `designSize` re-scales the entire app at once.** Every `context.w/h/r/sp` call resolves against it, and a window narrower or shorter than the artboard shrinks the design by that ratio — moving from 375×812 to 390×844 shrinks everything on a 375-wide phone. Change it only when your design source of truth actually changed, then sweep the app on a small phone, a tall phone and a tablet.

Both sides of `designSize` — and of every profile's `designSize` — must be positive: a zero side divides by zero. `ResponsiveInit` asserts it for every profile on build, and `ResponsiveMetrics` again when it scales. A window with no area yet (Android reports 0×0 for the first frame) is read as the artboard itself, factor 1, not as 0 — so that frame is not laid out with every value collapsed to nothing. `ScaleBounds.clamp` reads a NaN factor as 1 as well, then clamps it.

---

## 6. Scale policy: down by default, up on opt-in, per window class

A scale factor is the window-to-artboard ratio on one axis. Left alone it grows without limit: a 1280-wide desktop window against the 375-wide artboard is 3.4×, so 20 px text renders at 68 px and a title clips. `core_responsive` therefore clamps every factor with a `ScaleBounds`:

| Bounds | Range | Use for |
|---|---|---|
| `ScaleBounds.downOnly()` — **the default** | 0 – 1 | Shrink on a window smaller than the artboard, draw 1:1 on a larger one. The extra room goes to the layout (§7), not to bigger pixels |
| `ScaleBounds(max: 1.2)` | 0 – 1.2 | Opt-in, capped growth. Add `min:` to stop shrinking where text would stop being readable or targets tappable |
| `ScaleBounds.fixed()` | 1 – 1 | Always the design size — for a class laid out in real logical pixels |
| `ScaleBounds.unbounded()` | 0 – ∞ | The raw ratio, the behaviour before bounds existed. Rarely right for an app that runs on more than one form factor |

Layout and text are bounded **separately**: `scaleBounds` clamps `w` and `h` (and the `r` / `dg` / `dm` built from them), `textScaleBounds` clamps the factor behind `sp`. A tablet can afford wider gutters long before it can afford bigger body text.

A **`ResponsiveProfile`** overrides the artboard, both bounds and `minTextAdapt` for one `WindowSizeClass` (§7); a field left `null` inherits the top-level value. The profile that applies is the one keyed by the window's class, else the one keyed by the nearest **smaller** class, else none — so a profile at `expanded` also covers `large` and `extraLarge` until they declare their own, the way a `min-width` media query cascades.

This is the app's whole configuration:

```dart
// platform/shell/app_shell/lib/main_scope.dart — _ResponsiveWrapper.build
return ResponsiveInit(
  // The phone artboard every window class starts from.
  designSize: AppConfig.design,
  // Left at their defaults, `scaleBounds` and `textScaleBounds` are
  // `ScaleBounds.downOnly()`: a phone narrower than the artboard scales
  // the design down to fit, and nothing ever scales up — a tablet or a
  // desktop window draws it 1:1 and gives the extra room to the layout
  // (see `AdaptiveLayout`). To let a class grow, opt in with a bound:
  // `ResponsiveProfile(scaleBounds: ScaleBounds(max: 1.2))`.
  profiles: const {
    // Tablets in landscape, unfolded foldables and desktop windows are
    // laid out in real logical pixels. (Phones never get here: the
    // shell locks phone-sized displays to portrait — see
    // `AppInitializer.preferredOrientationsFor`.) Without this, a laptop window
    // shorter than the 812-tall phone artboard would still shrink every
    // vertical gap and radius.
    WindowSizeClass.expanded: ResponsiveProfile(
      scaleBounds: ScaleBounds.fixed(),
      textScaleBounds: ScaleBounds.fixed(),
    ),
  },
  // Keeps height scaling sane when the app is a short split-screen pane.
  splitScreenMode: true,
  child: child,
);
```

What that gives, window by window:

| Window | Class | Result |
|---|---|---|
| Phone narrower than 375 | `compact` | Shrinks to fit: `w` and `sp` by the width ratio, `h` by the height ratio |
| Phone 375 wide or more | `compact` | `w` and `sp` 1:1. `h` and `r` still shrink on a phone shorter than 812 — never below 700/812, thanks to `splitScreenMode` |
| 600–839 wide | `medium` | As the row above: `downOnly` stops every factor at 1 |
| 840 wide or more | `expanded` and up | 1:1 on every axis (`fixed`), however short the window |

| Parameter | Default | This app | What it does |
|---|---|---|---|
| `designSize` | 360×690 | `AppConfig.design` (375×812) | The artboard every class measures against, unless its profile names another |
| `scaleBounds` | `ScaleBounds.downOnly()` | default | Range of the layout factors: `w`, `h`, and the `r` / `dg` / `dm` built from them |
| `textScaleBounds` | `ScaleBounds.downOnly()` | default | Range of the text factor behind `sp`. Independent of `scaleBounds` |
| `profiles` | `{}` | `expanded` → `fixed` / `fixed` | `Map<WindowSizeClass, ResponsiveProfile>`: per-class `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` (`null` inherits). Exact class first, else the nearest smaller one |
| `breakpoints` | `ResponsiveBreakpoints.material3()` | default | Where each window size class begins (§7). The profiles and `context.windowSizeClass` both classify with it |
| `minTextAdapt` | `false` | default | `true` scales text by the **smaller** of the width and height ratios instead of the width — no ballooning on a wide, short window, but smaller text in landscape |
| `splitScreenMode` | `false` | `true` | Floors the height used for vertical scaling at `ResponsiveConstants.SPLIT_SCREEN_MIN_HEIGHT` (700), so a short split-screen pane does not collapse every `h` |
| `fontSizeResolver` | `null` | not set | Replaces text scaling **entirely**, and its result is **never clamped** — no `textScaleBounds`, no profile, no `minTextAdapt`. Read `metrics.effectiveTextScaleBounds` inside it to honour the bounds |

**Opting into growth** is one profile per class that should grow, with a cap:

```dart
// Illustrative — not in the template: medium windows may grow 20 %, text 10 %.
WindowSizeClass.medium: ResponsiveProfile(
  scaleBounds: ScaleBounds(max: 1.2),
  textScaleBounds: ScaleBounds(max: 1.1),
),
```

Check two things when you do. A class that grows meets its neighbour in a **visible step**: next to this app's `fixed` expanded profile, the example lays out at 1.2× at 839 wide and at 1× at 840. And a profile `designSize` wider than the first width of its class (600 for `medium`, 840 for `expanded`) makes everything shrink the moment the window enters that class; one no wider starts at a ratio of 1 or more, which `downOnly` draws 1:1 on both sides of the boundary.

`context.responsive` exposes what was resolved — `activeProfile`, `effectiveDesignSize`, `effectiveScaleBounds`, `effectiveTextScaleBounds`, `effectiveMinTextAdapt`, `windowSizeClass`, `orientation` — for a debug overlay or a test.

> [!NOTE]
> Rebuilding needs no configuration. `ResponsiveInit` is a `StatelessWidget` that reads `MediaQuery.sizeOf(context)` — a size-only dependency — and publishes `ResponsiveMetrics` through the `ResponsiveScope` `InheritedWidget`. Every `context.w/h/r/sp` call registers a dependency on that scope, so Flutter rebuilds exactly the widgets that read a scaled value. This is why there is no `num` extension: `16.w` could only read a global, and a global cannot notify anyone. `arch_check` rule R7 enforces it.

> [!TIP]
> `ResponsiveScope.of(context)` asserts when no `ResponsiveInit` is above it, rather than silently returning unscaled values. A widget test that scales must wrap its subject in `ResponsiveInit`.

---

## 7. Adaptive layouts: tablets, foldables, split screen

§6 decides how big to draw; this section decides **what** to draw with the room a larger window gives — more columns, a side rail, a second pane. Everything here lives in `core_responsive` (`platform/ui/responsive/lib/src/adaptive/`) and classifies the **window**, not the device: an iPad in Split View, a desktop window dragged narrow and a foldable's cover screen each get the class of the space the app actually has. Unlike `context.w`, none of it needs a `ResponsiveInit` — without one, the window is classified with the Material 3 defaults.

### Window size classes

| `WindowSizeClass` | Width (logical px) | Typical window |
|---|---|---|
| `compact` | < 600 | Phone in portrait; a flip phone, open or half folded; a narrow split-screen pane |
| `medium` | 600 – 839 | Tablet or foldable in portrait; a half-screen split on a large tablet |
| `expanded` | 840 – 1199 | Tablet in landscape (iPad); an unfolded foldable; a small desktop window |
| `large` | 1200 – 1599 | Large tablet in landscape; a desktop window |
| `extraLarge` | ≥ 1600 | A large desktop window |

A phone in landscape is `medium` or `expanded` by width — though this app never shows one: `AppInitializer` locks phone-sized displays (shortest side below 600) to portrait and leaves larger ones unlocked (`AppInitializer.preferredOrientationsFor`). If you lift that lock, `context.windowHeightClass` tells a landscape phone apart: `WindowHeightClass.compact` below 480, `medium` 480–899, `expanded` from 900.

The boundaries are a `ResponsiveBreakpoints` — `const ResponsiveBreakpoints.material3()` by default, values in `ResponsiveConstants.BREAKPOINT_*`. Pass another set to `ResponsiveInit(breakpoints:)` and the scale profiles, `context.windowSizeClass` and every widget below move together. Compare classes with `isAtLeast` / `isSmallerThan`, never with raw widths.

### A value per class: `context.adaptive`

```dart
// from the doc comment in platform/ui/responsive/lib/src/adaptive/adaptive_context_extension.dart
final columns = context.adaptive(compact: 1, expanded: 3);
// compact 1 · medium 1 · expanded 3 · large 3 · extraLarge 3
```

A class given no value falls back to the nearest **smaller** class that has one, ending at the required `compact` — so adding a breakpoint never changes the narrower layouts that already work. Shorthands: `context.isCompactWindow`, `context.isExpandedOrWider`.

### A subtree per class: `AdaptiveLayout`

```dart
AdaptiveLayout(
  compact: (_) => const InboxList(),
  expanded: (_) => const InboxWithPreview(),
)
```

Same fallback: `medium` shows the list, `large` and `extraLarge` the preview. Slots are builders, so only the layout on screen is built — and crossing into a class served by another builder replaces the subtree, taking scroll offsets and typed text with it. Keep state that must survive a rotation or a resize in the route-level controller, above this widget. `AdaptiveBuilder(builder: (context, windowSizeClass) => …)` does the same for a branch written in code.

### Master–detail: `AdaptiveSplitView`

```dart
// from the doc comment in platform/ui/responsive/lib/src/adaptive/adaptive_split_view.dart
AdaptiveSplitView(
  primary: MailList(
    // `itemContext` is the tapped item's: below the split view.
    onOpen: (itemContext, id) => AdaptiveSplitView.isSplit(itemContext)
        ? setState(() => _openId = id) // shown in the secondary pane
        : MailRoute(id: id).push(itemContext), // one pane: push it
  ),
  secondary: _openId == null ? null : MailView(id: _openId!),
  secondaryPlaceholder: const NothingSelected(),
)
```

It splits by the first rule that applies:

1. **A vertical fold or hinge** (`FoldPosture.book`) — side by side, divided exactly at it, nothing drawn under it. Wins even below `splitAt`: a half-opened foldable has two physical halves.
2. **A horizontal fold** (`FoldPosture.tabletop`) while `tabletopSplit` is `true` (the default) — `primary` above, `secondary` below. Turn it off for content that must not be cut in half, such as a form.
3. **A window of `splitAt` or wider** (default `WindowSizeClass.expanded`) — side by side, `primary` taking `primaryWidth` or `primaryFraction` (0.4) of the width, with an optional `divider` laid out `dividerExtent` wide (default 1). `primary` is capped so the divider and `secondary` still fit; a `primaryWidth` that leaves `secondary` nothing falls through to rule 4 instead of drawing a zero-width pane, so `isSplit` never reports a pane that is not there.
4. **Otherwise** — `primary` alone. `secondary` is not built, so the app pushes the item's route instead; `AdaptiveSplitView.isSplit(context)` is how the list item knows which to do. Its `context` must be *below* the view — inside a pane, or through a `Builder`.

`primary` sits at the start edge (the right, under RTL). Both panes keep their place in the tree whichever rule applies, so the list's scroll offset and any typed text survive a rotation or the device being unfolded. The view needs a bounded box — not directly inside a scroll view or an unconstrained `Row` / `Column`.

**Folds.** `context.separatingDisplayFeature` is the fold or hinge dividing the window: a hinge always; a fold only while half opened (`DisplayFeatureState.postureHalfOpened`), because opened flat it is one continuous screen; a camera cutout never — `SafeArea` handles those. `context.foldPosture` names the result: `FoldPosture.flat`, `book` (a Galaxy Z Fold or Pixel Fold half open) or `tabletop` (a Galaxy Z Flip half folded on a table).

> [!WARNING]
> **The fold rules apply only when the view spans the window along the fold.** A fold's bounds are in window coordinates, and a widget cannot learn where it sits until after layout. So rule 1 needs the view exactly as wide as the window and rule 2 exactly as tall; anywhere else the fold is ignored and rules 3–4 decide. Make the view the route's full body and put side chrome inside `primary`. Inside a dashboard tab that costs one rule each: from `medium` up the rail takes width, so a book fold is ignored; on `compact` the bottom bar takes height, so a tabletop fold is. A split view that must honour both belongs in a stack route (`IFeatureRouteModule`) whose whole body is the view.

### A readable width: `AdaptiveContent`

```dart
// modules/auth/feature/lib/src/pages/login_page.dart
child: SingleChildScrollView(
  padding: EdgeInsets.all(AppSpacing.xl(context)),
  // On a tablet or desktop window the form keeps a readable width
  // instead of stretching across the screen.
  child: AdaptiveContent(
    child: Consumer<AuthProvider>(
      // …
    ),
  ),
),
```

It caps its child at `maxWidth` — `AdaptiveConstants.CONTENT_MAX_WIDTH`, 640 — and places it at the top centre of the space left. On a phone the window is narrower than the cap, so nothing changes. `maxWidth` is in **window pixels and never scaled**: it answers how long a line may get, which the reader's eye settles, not the artboard — wrapped in `context.w`, it would grow with the very ratio it exists to stop. `padding`, like any reusable widget's parameter, is used as given: scale it at the call site.

### The reference: navigation chrome per window class

`feature_dashboard` switches its chrome on the window size class: a bottom bar on `compact`, a `NavigationRail` from `medium` up, extended (labels beside the icons) from `large` up. Both are built from the same `NavDestination`s each tab contributes through `INavDestinationModule`, so no tab knows which one is showing.

```dart
// modules/dashboard/feature/lib/src/pages/dashboard_page.dart
final sizeClass = context.windowSizeClass;
if (sizeClass.isSmallerThan(WindowSizeClass.medium)) {
  return Scaffold(
    body: navigationShell,
    bottomNavigationBar: BottomNavigationBar(
      // …
    ),
  );
}

final extended = sizeClass.isAtLeast(WindowSizeClass.large);
// The rail sits at the start edge — the right in RTL — so only its outer
// side pads for the insets.
final isRtl = Directionality.of(context) == TextDirection.rtl;
return Scaffold(
  body: Row(
    children: [
      SafeArea(
        left: !isRtl,
        right: isRtl,
        child: NavigationRail(
          // …
          extended: extended,
          // …
        ),
      ),
      Expanded(child: navigationShell),
    ],
  ),
);
```

The whole page, and what the dashboard must not own: [`../architecture/05_features.md`](../architecture/05_features.md#4-feature_dashboard-is-chrome-only).

---

## 8. Add a new token class

Say you want `AppElevation`. Follow the shape the existing classes use — private constructor, `raw*` constants, context-taking accessors.

**Step 1** — create `platform/ui/design_system/lib/src/styles/app_elevation.dart`:

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
dart tools/barrel_generator/generate.dart platform/ui/design_system/lib
```

`styles/styles.dart` is auto-generated — never hand-edit it; the generator strips manual `export` lines on the next run.

**Step 3** — use it. `core_base_ui`'s public barrel already re-exports `styles/`, so any feature gets it for free:

```dart
Material(elevation: AppElevation.raised(context), child: …)
```

---

## 9. Gradients and shadows

`AppGradients` reads live theme colours, so gradients recolour with the palette automatically:

```dart
// platform/ui/design_system/lib/src/styles/app_gradients.dart
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
// platform/ui/design_system/lib/src/styles/app_shadows.dart
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

## 10. The rules that stay

Full list in [`../reference/01_rules.md`](../reference/01_rules.md). Which of these a machine holds is stated per rule, because it changes how much you can rely on review catching it.

- **Never hard-code** a `Color`, `fontSize`, spacing number or `BorderRadius` in a widget. Missing a token? Add it to `core_base_ui` — do not inline the value. *Review-held.* See the note below for why.
- **Every dimension scales.** A bare `SizedBox(height: 24)` is a bug; write `SizedBox(height: context.h(24))` or `context.verticalSpace(24)`. *`arch_check` R7 holds the bare-extension half (`24.h`); the raw-double half is review-held.*
- **A widget scales its own constants, never its parameters.** A `core_ui_kit` widget receives already-scaled values — the caller scaled them — so using a parameter raw is correct and `context.w(widget.width)` is a double-scale bug. Its *own* padding and radii it must scale, or it is not responsive. `custom_input_field.dart` shows both in one line: `widget.paddingBottom ?? context.h(10)`. *Review-held.*
- **Do not scale an already-scaled value.** `AppSpacing.lg(context)` is final; `context.w(AppSpacing.lg(context))` is a double-scale bug. Likewise `AppTextStyles.bodyMediumStyle(context).copyWith(fontSize: ...)` — `ThemeProvider` already scaled every step, so overriding the size discards the scale and pins a number the design system cannot change. Reach for a different step instead. *Review-held.*
- **Edit `raw*`, not the accessor**, when retuning a scale.
- **Do not expect sizes to grow on a tablet.** Every factor stops at 1:1 by default; spend the extra room on layout (§7). Growth is an opt-in per window class, with a cap (§6). *Held by `ResponsiveInit`'s defaults.*
- **Choose a layout by window size class** — `context.windowSizeClass`, `context.adaptive`, `AdaptiveLayout` — never by device model, `Platform.isIOS` or an ad-hoc `shortestSide` check. One device shows many windows: Split View, a cover screen, a resized desktop window. *Review-held.*

> [!NOTE]
> **Why the colour and font-size rules are not machine-checked.**
>
> They were considered and deliberately left to review. A check for `Colors.<name>` would have to allow the places a literal colour is *correct* — `AppShadows`, which is the token file, and every modal scrim, where Flutter's own `ModalBarrier` is a fixed black and a theme-aware value would *lighten* the screen in dark mode. On this tree that is seven approved uses against two real ones, and a rule whose exception list outweighs its findings teaches people to skim it.
>
> The repo also forbids suppression comments, so there is no honest escape hatch for the legitimate cases. Review it is — which is exactly why three dark-mode bugs survived in `core_ui_kit` until they were audited for, and worth knowing when you copy a widget out of it.

---

## 11. Quick lookup

| I want to change… | Edit |
|---|---|
| A brand colour | `theme/theme_system_extensions.dart` → `light` **and** `dark` |
| Add a colour slot | `theme/theme_system_interface.dart`, then both palettes + `lerp` |
| The typeface | `pubspec.yaml` → `flutter: fonts:` + `theme/theme_provider.dart` → `applyFont` |
| A font size in the ramp | `theme/theme_provider.dart` → the `copyWith` block |
| A spacing step | `styles/app_spacing.dart` → the `raw*` constant |
| A corner radius | `styles/app_radius.dart` → the `raw*` constant |
| A gradient | the colour list in `theme/theme_system_extensions.dart` |
| A shadow | `styles/app_shadows.dart` |
| The design canvas | `platform/foundation/common/lib/src/config/app_config.dart` → `design` |
| How far a window class may scale (bounds, profiles, breakpoints) | `platform/shell/app_shell/lib/main_scope.dart` → `ResponsiveInit` (§6) |
| The layout on a tablet, foldable or split screen | the page — `context.adaptive`, `AdaptiveLayout`, `AdaptiveSplitView`, `AdaptiveContent` (§7) |
| Add a whole new token class | new file in `styles/`, then run the barrel generator |

---

## See also

- [`09_localization_theming.md`](09_localization_theming.md) — using tokens in widget code, and per-feature translations
- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_base_ui` sits, and why it ships zero widgets; the `core_responsive` public API
- [`../reference/01_rules.md`](../reference/01_rules.md) — the enforced rules, with the commands that verify them
