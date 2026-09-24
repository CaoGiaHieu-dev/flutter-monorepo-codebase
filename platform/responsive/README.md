🌍 *Choose Language:* [English](README.md) | [Tiếng Việt](README.vi.md)

# Core Responsive

A micro-core package providing **UI scaling against a design size** — shrink-only by default, growth opt-in per window class — plus **window size classes** and **adaptive layout widgets** for tablets, foldables and split screen.

All scaling goes through `BuildContext`. That is not a style convention — it is what makes widgets **rebuild in exactly the right places** when the screen size changes (rotation, split-screen, a desktop window resize).

---

## 🌟 Core Features

- **`ResponsiveInit`**: A widget mounted **exactly once**, above `MaterialApp`. Takes a `designSize` (the design artboard) and publishes metrics to the whole subtree.
- **`ResponsiveScope`**: The `InheritedWidget` carrying `ResponsiveMetrics`. Reading through it **registers a dependency**, so Flutter takes care of targeted rebuilds.
- **`ResponsiveMetrics`**: An immutable value object holding all the scaling maths (`scaleWidth`, `scaleHeight`, `scaleText`, `width`, `height`, `radius`, `diagonal`, `diameter`, `sp`, `spMin`), the resolved values (`activeProfile`, `effectiveDesignSize`, `effectiveScaleBounds`, `effectiveTextScaleBounds`, `effectiveMinTextAdapt`) and `windowSizeClass`, `windowHeightClass`, `orientation`.
- **`ScaleBounds`**: The range a scale factor may take — `downOnly()` (the default), `fixed()`, `unbounded()`, or `ScaleBounds(min:, max:)`.
- **`ResponsiveProfile`**: Overrides `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` for one `WindowSizeClass`.
- **`WindowSizeClass` / `WindowHeightClass` / `ResponsiveBreakpoints`**: Classifies the **window** (not the device) by the Material 3 breakpoints.
- **`ResponsiveContext`**: An extension on `BuildContext` — `context.w`, `.h`, `.r`, `.sp`, `.spMin`, `.dg`, `.dm`, `.edgeInsets`, `.borderRadius`, `.verticalSpace`, `.horizontalSpace`, `.responsive`, `.windowSizeClass`, `.windowHeightClass`.
- **`AdaptiveContext`**: An extension on `BuildContext` — `context.adaptive(...)`, `.isCompactWindow`, `.isExpandedOrWider`, `.separatingDisplayFeature`, `.foldPosture`.
- **`AdaptiveBuilder` / `AdaptiveLayout` / `AdaptiveSplitView` / `AdaptiveContent`**, **`FoldPosture`**: Adaptive layout widgets — see §3.
- **`ResponsiveConstants`** / **`AdaptiveConstants`**: The package's constants (`SPLIT_SCREEN_MIN_HEIGHT = 700`, the default `360x690` design, the width and height `BREAKPOINT_*`s; `SPLIT_PRIMARY_FRACTION = 0.4`, `SPLIT_DIVIDER_EXTENT = 1`, `CONTENT_MAX_WIDTH = 640`).

---

## 🚀 1. Setup

Already wired in `platform/app_shell/lib/main_scope.dart`. A feature **never** mounts its own `ResponsiveInit`. The app's real configuration (comments trimmed) — `AppConfig.design` is a `375x812` artboard, not the package's `360x690` default:

```dart
// platform/app_shell/lib/main_scope.dart — _ResponsiveWrapper.build
return ResponsiveInit(
  // The phone artboard every window class starts from.
  designSize: AppConfig.design,
  // …
  profiles: const {
    // …
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

`ResponsiveInit` is a `StatelessWidget` — on purpose. It reads `MediaQuery.sizeOf(context)`, which registers a dependency on the **size aspect** only, so it rebuilds on a resize and stays put when brightness / text scale / padding change. No `WidgetsBindingObserver`, no `setState`.

| Parameter | Default | Meaning |
|:--|:--|:--|
| `designSize` | `360x690` | The artboard the design was drawn at — every window class is measured against it unless a profile names another |
| `scaleBounds` | `ScaleBounds.downOnly()` | Range of the layout factors: `w`, `h`, and the `r` / `dg` / `dm` built from them |
| `textScaleBounds` | `ScaleBounds.downOnly()` | Range of the text factor behind `sp`, independent of `scaleBounds` |
| `profiles` | `{}` | `Map<WindowSizeClass, ResponsiveProfile>` — overrides `designSize`, `scaleBounds`, `textScaleBounds`, `minTextAdapt` per class (`null` inherits). The profile of the exact class applies, else that of the nearest smaller class that has one |
| `breakpoints` | `ResponsiveBreakpoints.material3()` | Where each window class starts: `compact` < 600 ≤ `medium` < 840 ≤ `expanded` < 1200 ≤ `large` < 1600 ≤ `extraLarge`; by height: `compact` < 480 ≤ `medium` < 900 ≤ `expanded` |
| `splitScreenMode` | `false` | Floors the height at `700` before dividing, so vertical scaling does not collapse to unreadable values in a very short window |
| `minTextAdapt` | `false` | Text scales by the smaller axis instead of by width |
| `fontSizeResolver` | `null` | Decide font sizes yourself. **Warning:** a resolver replaces text scaling entirely — `minTextAdapt` has no effect, and the result is **never clamped** by `textScaleBounds` or a profile (read `metrics.effectiveTextScaleBounds` inside the resolver to honour the bounds) |

### Scale policy: shrink by default, grow on opt-in

A scale factor is the window / artboard ratio, then clamped by a `ScaleBounds`. Unclamped, a 1280-wide window against a 375-wide artboard is 3.4× — a 20 px title renders at 68 px.

| Bound | Range | Meaning |
|:--|:--|:--|
| `ScaleBounds.downOnly()` — **default** | 0 – 1 | A window smaller than the artboard shrinks the design; a larger one draws it 1:1 and leaves the extra room to the layout |
| `ScaleBounds(max: 1.2)` | 0 – 1.2 | Bounded growth — opt-in |
| `ScaleBounds.fixed()` | 1 – 1 | Always the design size |
| `ScaleBounds.unbounded()` | 0 – ∞ | The raw ratio, the behaviour before bounds existed |

So **do not expect sizes to grow on a tablet**. To let a window class grow, opt that class in with a `ResponsiveProfile`; a profile set on one class also covers every wider class that has none of its own. Details: [`docs/en/guides/11_design_system.md`](../../docs/en/guides/11_design_system.md) §6.

---

## 📏 2. Usage

```dart
SizedBox(height: context.h(24)),
Text('Hi', style: TextStyle(fontSize: context.sp(16))),
Container(
  width: context.w(280),
  padding: context.edgeInsets(horizontal: 16, vertical: 8),
  decoration: BoxDecoration(borderRadius: context.borderRadius(all: 12)),
),
```

| Helper | Scales by |
|:--|:--|
| `context.w(x)` | Width — also for anything that must stay square |
| `context.h(x)` | Height — vertical gaps, row heights |
| `context.r(x)` | The smaller axis — radii, borders, stroke widths |
| `context.sp(x)` | Font size |
| `context.spMin(x)` | `sp` capped at the design value — text shrinks but never grows. Equal to `sp` under the default bounds; differs only when a profile or a `fontSizeResolver` lets text grow |
| `context.dg(x)` | Both axes |
| `context.dm(x)` | The larger axis |
| `context.edgeInsets(all:)` / `(horizontal:)` | `w` |
| `context.edgeInsets(vertical:)` | `h` |
| `context.edgeInsetsDirectional(start:)` / `(end:)` | `w` — `EdgeInsetsDirectional`, flips in RTL |
| `context.borderRadius(all:)` | `r` |
| `context.verticalSpace(x)` / `horizontalSpace(x)` | `h` / `w` |

Each axis scales by the axis it belongs to, so padding keeps its proportions instead of tracking a single dimension. That is why `context.edgeInsets(all: 16)` is a drop-in for `EdgeInsets.all(context.w(16))`.

---

## 🧩 3. Adaptive layout: tablets, foldables, split screen

Scaling decides how big to draw; this part decides **what** to draw. Everything is classified by the **window**, not the device, and works even without a `ResponsiveInit` above (the Material 3 breakpoints are used then).

```dart
// One value per class; a missing class takes the nearest smaller one.
final columns = context.adaptive(compact: 1, expanded: 3);

// One subtree per class.
AdaptiveLayout(
  compact: (_) => const InboxList(),
  expanded: (_) => const InboxWithPreview(),
)

// A form that does not stretch across a tablet or desktop window.
AdaptiveContent(child: form)
```

| Piece | Use it when |
|:--|:--|
| `context.windowSizeClass` / `windowHeightClass` | Asking for the window's class; compare with `isAtLeast` / `isSmallerThan` |
| `context.adaptive(compact:, medium:, …)` | Picking one value per class; `isCompactWindow`, `isExpandedOrWider` are shorthands |
| `AdaptiveLayout` / `AdaptiveBuilder` | Picking a whole subtree per class — only the layout on screen is built |
| `AdaptiveSplitView` | Master–detail: two panes at a vertical fold / hinge (even below `splitAt`), top–bottom at a horizontal fold (`tabletopSplit`, on by default), side by side from `splitAt` (default `expanded`; the primary pane takes `primaryFraction` = `0.4` or `primaryWidth`), otherwise the primary pane alone — `secondary` is not built. `AdaptiveSplitView.isSplit(context)` (called with a context **below** the split view) tells a list item whether to select or push a route |
| `AdaptiveContent` | Capping content width at `640` — window pixels, **not** scaled |
| `context.separatingDisplayFeature` / `foldPosture` | The fold or hinge dividing the window; `FoldPosture.flat` / `book` / `tabletop` |

> [!WARNING]
> `AdaptiveSplitView` honours a fold only when it spans the window along the fold (fold coordinates are window coordinates): as wide as the window for a vertical fold (`book`), as tall as the window for a horizontal one (`tabletop`). Beside a `NavigationRail` a vertical fold is ignored; under an app bar a horizontal one is — the `splitAt` rule decides instead.

**Choose a layout by window class, never by `Platform.isIOS`, device model or an ad-hoc `shortestSide` check.** Reference: `modules/dashboard/feature/lib/src/pages/dashboard_page.dart` — a bottom bar on `compact`, a `NavigationRail` from `medium`, extended from `large`. Details: [`docs/en/guides/11_design_system.md`](../../docs/en/guides/11_design_system.md) §7.

---

## ⛔ 4. There is no extension on `num`

`16.w` **does not compile**. The package deliberately ships no extension on `num`, and no global singleton to read from either.

Why: a number carries no context. A `16.w`-style extension could therefore only read a global — and a widget that reads a global **never learns the metrics changed**: it computes once and stops. That is a silent stale-value bug that stays hidden until the device rotates.

Requiring the context turns "the right thing" into "the only thing you can write". Rebuilds are Flutter's `InheritedWidget` job, so there is no flag to switch on or off.

## ⚠️ 5. Two traps

**In `async` code:** read the scaled value **before the first `await`**, then pass the result on. Never hold a `BuildContext` across an async gap.

```dart
final size = context.w(200).toInt();   // read first
final thumb = await _load(size);       // then await
```

**In widget tests:** a test of any widget that scales must wrap it in `ResponsiveInit`, or `ResponsiveScope.of` asserts:

```dart
await tester.pumpWidget(
  ResponsiveInit(designSize: const Size(360, 690), child: subject),
);
```

The assert is deliberate. Silently falling back to unscaled values would ship a layout that is wrong on every device except the design artboard, with nothing pointing at the cause.

---

## 🤖 6. Machine-enforced

`dart tools/arch_check/check.dart` — rule **R7**, Gate 1 of `pr_quality_check.yml` — scans every file under `lib/` that mentions `core_responsive` (in practice: imports it) and **blocks the merge** (exit 1) on any bare sizing extension (`16.w`, `(x).sp`, …), printing `file:line`. The rule does not depend on review.

The package's tests live in `platform/responsive/test/`.
