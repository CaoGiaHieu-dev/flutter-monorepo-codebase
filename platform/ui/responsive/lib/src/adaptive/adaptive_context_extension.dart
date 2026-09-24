import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

import '../context_extension.dart';
import 'fold_posture.dart';
import 'window_size_class.dart';

/// Layout decisions, routed through [BuildContext] — which layout to show,
/// not how big to draw it.
///
/// ## Why nothing here needs a `ResponsiveInit`
///
/// Unlike the scaling helpers, every member here works without a
/// `ResponsiveInit` above — `context.windowSizeClass` falls back the same
/// way. Choosing a layout is a
/// question about the window, and every Flutter app has one: a widget test,
/// a package preview or an app that never adopts design-size scaling can
/// still ask it. So the window size class is read from the `ResponsiveInit`
/// when there is one — honouring its breakpoints, so the whole app agrees
/// on where compact ends — and otherwise classified from [MediaQuery] with
/// the Material 3 defaults of [ResponsiveBreakpoints]. A scaling fallback
/// would ship a silently wrong number; this one returns the standard
/// answer.
///
/// Reading a member registers a dependency like any `.of(context)`: the
/// size-class members rebuild the reader on every resize (like a widget
/// that scales), the fold members when the display features change.
extension AdaptiveContext on BuildContext {
  /// Whether the window is [WindowSizeClass.compact]: a phone in portrait, a
  /// flip phone, a narrow split-screen pane. The usual one-pane,
  /// bottom-navigation layout.
  bool get isCompactWindow => windowSizeClass == WindowSizeClass.compact;

  /// Whether the window is [WindowSizeClass.expanded] or wider: room for two
  /// panes side by side.
  bool get isExpandedOrWider =>
      windowSizeClass.isAtLeast(WindowSizeClass.expanded);

  /// The value for the current window size class.
  ///
  /// A class given no value falls back to the nearest *smaller* class that
  /// has one, ending at the required [compact]:
  ///
  /// ```dart
  /// final columns = context.adaptive(compact: 1, expanded: 3);
  /// // compact 1 · medium 1 · expanded 3 · large 3 · extraLarge 3
  /// ```
  ///
  /// Falling back downwards means adding a breakpoint never changes the
  /// narrower layouts that already work: a value only ever takes effect
  /// from its own class up. `null` counts as "not given", so for a nullable
  /// `T` a class cannot opt back to `null` once a smaller one has a value.
  T adaptive<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
    T? extraLarge,
  }) {
    return switch (windowSizeClass) {
      WindowSizeClass.compact => compact,
      WindowSizeClass.medium => medium ?? compact,
      WindowSizeClass.expanded => expanded ?? medium ?? compact,
      WindowSizeClass.large => large ?? expanded ?? medium ?? compact,
      WindowSizeClass.extraLarge =>
        extraLarge ?? large ?? expanded ?? medium ?? compact,
    };
  }

  /// The fold or hinge that divides the window, or `null` when nothing does.
  ///
  /// - A **hinge** always divides it: it is a physical gap between two
  ///   screens, and content drawn over it is hidden.
  /// - A **fold** divides it only while half opened
  ///   ([DisplayFeatureState.postureHalfOpened]). Opened flat it is one
  ///   continuous screen, and splitting a layout at the crease would waste
  ///   the device's best posture.
  /// - A **cutout** (camera notch) never does; `SafeArea` handles those.
  ///
  /// With more than one (a tri-fold), this is the first. Its bounds are in
  /// the window's coordinates, not this widget's.
  DisplayFeature? get separatingDisplayFeature {
    for (final feature in MediaQuery.displayFeaturesOf(this)) {
      final separates = switch (feature.type) {
        DisplayFeatureType.hinge => true,
        DisplayFeatureType.fold =>
          feature.state == DisplayFeatureState.postureHalfOpened,
        _ => false,
      };
      if (separates) return feature;
    }
    return null;
  }

  /// How the window is divided right now — see [FoldPosture].
  FoldPosture get foldPosture => FoldPosture.of(separatingDisplayFeature);
}
