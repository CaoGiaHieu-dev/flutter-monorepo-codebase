import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/widgets.dart';

import '../context_extension.dart';
import '../utils/adaptive_constants.dart';
import 'adaptive_context_extension.dart';
import 'fold_posture.dart';
import 'window_size_class.dart';

/// Master–detail in one widget: a [primary] pane (the list) beside a
/// [secondary] one (the open item) when there is room for both, [primary]
/// alone when there is not.
///
/// ```dart
/// AdaptiveSplitView(
///   primary: MailList(
///     // `itemContext` is the tapped item's: below the split view.
///     onOpen: (itemContext, id) => AdaptiveSplitView.isSplit(itemContext)
///         ? setState(() => _openId = id) // shown in the secondary pane
///         : MailRoute(id: id).push(itemContext), // one pane: push it
///   ),
///   secondary: _openId == null ? null : MailView(id: _openId!),
///   secondaryPlaceholder: const NothingSelected(),
/// )
/// ```
///
/// ## When it splits, first rule that applies
///
/// 1. **A vertical fold or hinge** ([FoldPosture.book]): side by side,
///    divided exactly at it — [primary] ends at the fold's near edge,
///    [secondary] starts at its far edge, nothing is drawn under it. This
///    wins even below [splitAt]: a half-opened foldable has two physical
///    halves, and a hinge hides whatever straddles it.
/// 2. **A horizontal fold** ([FoldPosture.tabletop]) with [tabletopSplit]:
///    [primary] above the fold, [secondary] below it.
/// 3. **A window of [splitAt] or wider**: side by side, [primary] taking
///    [primaryWidth] or [primaryFraction] of the width — as long as that
///    leaves [secondary] some width once the [divider] is drawn. A
///    [primaryWidth] as wide as the view leaves none, and falls to rule 4.
/// 4. **Otherwise**: [primary] alone. [secondary] is not built, so the app
///    must show the open item another way — push its route, as above. The
///    same applies when a window narrows while an item is open: the view
///    drops back to the list, and it is the app's call whether to push the
///    item then.
///
/// [primary] sits at the start edge: on the left, or on the right under an
/// RTL [Directionality].
///
/// ## Placement: span the window along the fold
///
/// A fold's bounds are in window coordinates, and a widget cannot learn
/// where it sits in the window until after layout — too late to lay out by.
/// So rules 1 and 2 apply only when this view is exactly as wide as the
/// window (book) or as tall as it (tabletop): only then is its edge the
/// window's edge, and the fold's position exact. Anywhere else — beside a
/// `NavigationRail`, under an app bar in tabletop, inside another pane — the
/// fold cannot be placed, so it is ignored and rules 3 and 4 decide. Make
/// the view the route's full body and put side chrome inside [primary].
/// Flutter's `DisplayFeatureSubScreen` rests on the same limit, but assumes
/// its placement instead of checking it.
///
/// ## State survives a relayout
///
/// Both panes keep their position in the tree whichever rule applies, so
/// the list's scroll offset and any text being typed survive a rotation or
/// the device being unfolded. [secondary] is rebuilt fresh only after a
/// single-pane phase, since it was not in the tree during it.
class AdaptiveSplitView extends StatelessWidget {
  const AdaptiveSplitView({
    required this.primary,
    this.secondary,
    this.splitAt = WindowSizeClass.expanded,
    this.primaryFraction = AdaptiveConstants.SPLIT_PRIMARY_FRACTION,
    this.primaryWidth,
    this.divider,
    this.dividerExtent = AdaptiveConstants.SPLIT_DIVIDER_EXTENT,
    this.secondaryPlaceholder,
    this.tabletopSplit = true,
    super.key,
  }) : assert(
         primaryFraction > 0 && primaryFraction < 1,
         'primaryFraction must be between 0 and 1, exclusive.',
       ),
       assert(
         primaryWidth == null || primaryWidth > 0,
         'primaryWidth must be positive.',
       ),
       assert(
         dividerExtent >= 0 && dividerExtent < double.infinity,
         'dividerExtent must be finite and not negative.',
       );

  /// The pane that is always shown — typically the list.
  final Widget primary;

  /// The pane shown beside (or below) [primary] when split — typically the
  /// open item. `null` when nothing is open; see [secondaryPlaceholder].
  final Widget? secondary;

  /// The narrowest window class that shows both panes without a fold.
  ///
  /// Defaults to [WindowSizeClass.expanded]: on a medium window (600–839)
  /// each pane of a split would be phone-narrow, and neither would be
  /// usable.
  final WindowSizeClass splitAt;

  /// Share of the width [primary] takes in a split made by window class.
  final double primaryFraction;

  /// A fixed width for [primary], in logical pixels, used instead of
  /// [primaryFraction].
  ///
  /// Used as given, and capped so the [divider] and [secondary] still fit;
  /// when nothing is left for [secondary] the view shows [primary] alone
  /// (rule 4) rather than a zero-width pane. Scaling is the caller's
  /// call, as for every reusable widget: `context.w(360)` to grow it with
  /// the design, a plain `360` to keep the list the same width however wide
  /// the window gets.
  final double? primaryWidth;

  /// Drawn between the panes in a split made by window class, in a box
  /// [dividerExtent] wide and stretched to the full height — e.g.
  /// `ColoredBox(color: c)`.
  ///
  /// Not drawn at a fold or hinge: the hardware already divides the panes,
  /// and a zero-width fold has no room for one.
  final Widget? divider;

  /// The [divider]'s thickness, in logical pixels. Ignored without one.
  ///
  /// Given here rather than read off the divider because the split is
  /// decided before anything is laid out: the view has to know how much
  /// room the divider takes to know whether [secondary] still fits beside
  /// [primary] — and so what [isSplit] answers. The divider is laid out at
  /// exactly this width, whatever width it asks for itself. Used as given,
  /// like [primaryWidth]: scale it at the call site if it should scale.
  final double dividerExtent;

  /// Shown in the secondary pane while split and [secondary] is `null` —
  /// "select an item". Without one, the pane stays empty, which keeps
  /// [primary] from jumping in width when an item is opened.
  final Widget? secondaryPlaceholder;

  /// Whether a horizontal fold stacks the panes. Turn off for content that
  /// must not be cut in half — a document, a form — so a tabletop posture
  /// is treated like no fold at all.
  final bool tabletopSplit;

  /// Whether the nearest [AdaptiveSplitView] above [context] is showing
  /// both panes; `false` when there is none.
  ///
  /// Asks the view itself, so it agrees with what is on screen — including
  /// the fold and placement rules, which window size classes alone cannot
  /// see. [context] must be *below* the view: inside a pane, or through a
  /// `Builder`. Registers a dependency, so a build that reads it rebuilds
  /// when the answer changes.
  static bool isSplit(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitScope>()?.isSplit ??
      false;

  // Keyed so the panes are matched by identity, not position: whatever sits
  // between them as the layout switches rules, each keeps its element and
  // state.
  static const _primaryKey = ValueKey<String>('AdaptiveSplitView.primary');
  static const _secondaryKey = ValueKey<String>(
    'AdaptiveSplitView.secondary',
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedWidth && constraints.hasBoundedHeight,
          'AdaptiveSplitView needs a bounded box to divide. Do not put it '
          'directly inside a scroll view or an unconstrained Row/Column.',
        );
        final size = constraints.biggest;
        final split = _resolveSplit(context, size);
        final axis = split?.axis ?? Axis.horizontal;

        return _SplitScope(
          isSplit: split != null,
          child: Flex(
            direction: axis,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sized(
                axis,
                split?.primaryExtent ?? size.width,
                key: _primaryKey,
                child: primary,
              ),
              if (split != null) ...[
                if (split.foldExtent case final foldExtent?)
                  _sized(axis, foldExtent)
                else if (divider case final divider?)
                  _sized(axis, dividerExtent, child: divider),
                Expanded(
                  key: _secondaryKey,
                  child:
                      secondary ??
                      secondaryPlaceholder ??
                      const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Applies the rules in the class docs, in order. `null` means one pane.
  _Split? _resolveSplit(BuildContext context, Size size) {
    if (context.separatingDisplayFeature case final feature?) {
      final bounds = feature.bounds;
      final window = MediaQuery.sizeOf(context);
      final ltr = Directionality.of(context) == TextDirection.ltr;
      final atFold = switch (FoldPosture.of(feature)) {
        // Bounds are measured from the window's left edge, so under RTL the
        // primary pane is the part right of the fold.
        FoldPosture.book when _spans(size.width, window.width) => _Split(
          Axis.horizontal,
          ltr ? bounds.left : size.width - bounds.right,
          foldExtent: bounds.width,
        ),
        FoldPosture.tabletop
            when tabletopSplit && _spans(size.height, window.height) =>
          _Split(Axis.vertical, bounds.top, foldExtent: bounds.height),
        // A fold this view cannot place, or one it was told to ignore.
        _ => null,
      };
      // A fold at the view's very edge leaves one side nothing to show.
      if (atFold != null &&
          atFold.primaryExtent > precisionErrorTolerance &&
          atFold.remainingIn(size) > precisionErrorTolerance) {
        return atFold;
      }
    }

    if (context.windowSizeClass.isSmallerThan(splitAt)) return null;
    // What the panes share once the divider has its width. The primary pane
    // is capped at it, so the row can never overflow; if that leaves the
    // secondary pane nothing, this is one pane, not two with one invisible —
    // `isSplit` must not tell the list that its item is shown beside it.
    final available = size.width - (divider == null ? 0 : dividerExtent);
    final extent = math.min(
      primaryWidth ?? size.width * primaryFraction,
      math.max(available, 0.0),
    );
    if (available - extent <= precisionErrorTolerance) return null;
    return _Split(Axis.horizontal, extent);
  }

  static bool _spans(double extent, double windowExtent) =>
      (extent - windowExtent).abs() <= precisionErrorTolerance;

  /// A box [extent] long along [axis]; the [Flex] stretches the other side.
  static Widget _sized(Axis axis, double extent, {Key? key, Widget? child}) {
    return SizedBox(
      key: key,
      width: axis == Axis.horizontal ? extent : null,
      height: axis == Axis.vertical ? extent : null,
      child: child,
    );
  }
}

/// Where an [AdaptiveSplitView] divides its box.
class _Split {
  const _Split(this.axis, this.primaryExtent, {this.foldExtent});

  /// [Axis.horizontal]: side by side. [Axis.vertical]: stacked (tabletop).
  final Axis axis;

  /// The primary pane's length along [axis].
  final double primaryExtent;

  /// Thickness of the fold or hinge kept clear between the panes — zero for
  /// a fold, the gap for a hinge — or `null` for a split by window class.
  final double? foldExtent;

  /// What is left for the secondary pane in a view of [size].
  double remainingIn(Size size) =>
      (axis == Axis.horizontal ? size.width : size.height) -
      primaryExtent -
      (foldExtent ?? 0);
}

/// Publishes whether the [AdaptiveSplitView] above is split, for
/// [AdaptiveSplitView.isSplit].
class _SplitScope extends InheritedWidget {
  const _SplitScope({required this.isSplit, required super.child});

  final bool isSplit;

  @override
  bool updateShouldNotify(_SplitScope oldWidget) =>
      isSplit != oldWidget.isSplit;
}
