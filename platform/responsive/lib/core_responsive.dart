/// Design-size based responsive scaling, scoped to `BuildContext`.
///
/// Mount [ResponsiveInit] once above `MaterialApp`, then scale every dimension
/// through the context extensions: `context.w(16)`, `context.h(24)`,
/// `context.r(8)`, `context.sp(14)`.
///
/// ## Scale down by default, scale up by choice
///
/// Every factor is the window-to-design ratio clamped by a [ScaleBounds].
/// The default, [ScaleBounds.downOnly], shrinks a design to fit a window
/// smaller than its artboard and draws it 1:1 in a larger one — an unbounded
/// ratio would render a 375-wide phone design at 3.4x on a 1280-wide desktop
/// window. Growth is opt-in and capped, per axis family (`scaleBounds` for
/// layout, `textScaleBounds` for text) and per window class
/// ([ResponsiveProfile], keyed by [WindowSizeClass]), each against the design
/// size configured for that class:
///
/// ```dart
/// ResponsiveInit(
///   designSize: const Size(375, 812),
///   profiles: const {
///     WindowSizeClass.medium: ResponsiveProfile(
///       designSize: Size(600, 960),
///       scaleBounds: ScaleBounds(max: 1.25),
///     ),
///   },
///   child: const RootApp(),
/// )
/// ```
///
/// ## Why this lives here instead of a pub package
///
/// The maths is ~20 lines; the value is in the *contract*. A `num` extension
/// (`16.w`) has to read a global, and a widget that reads a global never finds
/// out the metrics changed — the number is right on first build and silently
/// stale after a rotation. This package exposes no global, so that failure is
/// not expressible.
library core_responsive;

// Auto-generated exports, do not edit manually.
export 'src/src.dart';
