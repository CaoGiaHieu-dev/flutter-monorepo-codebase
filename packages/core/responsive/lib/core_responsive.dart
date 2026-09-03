/// Design-size based responsive scaling, scoped to `BuildContext`.
///
/// Mount [ResponsiveInit] once above `MaterialApp`, then scale every dimension
/// through the context extensions: `context.w(16)`, `context.h(24)`,
/// `context.r(8)`, `context.sp(14)`.
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
