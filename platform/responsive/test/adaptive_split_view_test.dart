import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _primary = ValueKey('primary');
const _secondary = ValueKey('secondary');
const _placeholder = ValueKey('placeholder');
const _divider = ValueKey('divider');

/// Sets the window to [size] with [displayFeatures] and pumps [child].
Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child, {
  List<DisplayFeature> displayFeatures = const [],
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0
    ..displayFeatures = displayFeatures;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(textDirection: textDirection, child: child),
  );
}

/// A split view whose panes are empty boxes, findable by key.
AdaptiveSplitView _splitView({
  bool withSecondary = true,
  WindowSizeClass splitAt = WindowSizeClass.expanded,
  double primaryFraction = 0.4,
  double? primaryWidth,
  bool withDivider = false,
  double dividerExtent = 2,
  bool withPlaceholder = false,
  bool tabletopSplit = true,
  Widget primary = const SizedBox.expand(key: _primary),
}) {
  return AdaptiveSplitView(
    primary: primary,
    secondary: withSecondary ? const SizedBox.expand(key: _secondary) : null,
    splitAt: splitAt,
    primaryFraction: primaryFraction,
    primaryWidth: primaryWidth,
    divider: withDivider ? const SizedBox.expand(key: _divider) : null,
    dividerExtent: dividerExtent,
    secondaryPlaceholder: withPlaceholder
        ? const SizedBox.expand(key: _placeholder)
        : null,
    tabletopSplit: tabletopSplit,
  );
}

Rect _rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

DisplayFeature _halfOpenedFold(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

/// A Surface Duo-style hinge: a 20-wide gap between two screens.
const _hinge = DisplayFeature(
  bounds: Rect.fromLTRB(280, 0, 300, 800),
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.postureFlat,
);

/// Records every State it creates, to prove a pane was kept, not rebuilt.
class _Probe extends StatefulWidget {
  const _Probe();

  static final created = <State<_Probe>>[];

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created.add(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: _primary);
}

void main() {
  group('by window class', () {
    testWidgets('below splitAt: the primary pane alone, full size', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(700, 800), _splitView());

      expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 700, 800));
      // Not merely hidden: the app is expected to push it as a route.
      expect(find.byKey(_secondary), findsNothing);
    });

    testWidgets('at splitAt: side by side, primary at the fraction', (
      tester,
    ) async {
      // 840 is the first expanded width.
      await _pumpAt(tester, const Size(840, 800), _splitView());

      expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 336, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(336, 0, 840, 800),
      );
    });

    testWidgets('splitAt moves the line', (tester) async {
      await _pumpAt(
        tester,
        const Size(700, 800),
        _splitView(splitAt: WindowSizeClass.medium, primaryFraction: 0.5),
      );

      expect(_rectOf(tester, _primary).width, 350);
      expect(_rectOf(tester, _secondary).width, 350);
    });

    testWidgets('primaryWidth wins over the fraction, capped at the view', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(primaryFraction: 0.5, primaryWidth: 320),
      );
      expect(_rectOf(tester, _primary).width, 320);
      expect(_rectOf(tester, _secondary).width, 680);

      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(primaryWidth: 900, withDivider: true),
      );
      expect(_rectOf(tester, _primary).width, 900);
      expect(_rectOf(tester, _divider), const Rect.fromLTRB(900, 0, 902, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(902, 0, 1000, 800),
      );
    });

    // A primaryWidth that leaves the secondary pane nothing — as wide as the
    // view, or wide enough that the divider eats the rest — is one pane.
    // It used to overflow the row by the divider's width while `isSplit`
    // said true over a zero-width secondary pane.
    for (final (label, primaryWidth, withDivider) in [
      ('wider than the view', 5000.0, false),
      ('as wide as the view', 1000.0, false),
      ('wider than the view, with a divider', 5000.0, true),
      ('as wide as the view, with a divider', 1000.0, true),
      ('leaving only the divider room', 998.0, true),
      ('leaving less than the divider', 999.0, true),
    ]) {
      testWidgets('primaryWidth $label: one pane, no overflow', (
        tester,
      ) async {
        late bool answer;
        await _pumpAt(
          tester,
          const Size(1000, 800),
          _splitView(
            primaryWidth: primaryWidth,
            withDivider: withDivider,
            primary: Builder(
              builder: (context) {
                answer = AdaptiveSplitView.isSplit(context);
                return const SizedBox.expand(key: _primary);
              },
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 1000, 800));
        expect(find.byKey(_secondary), findsNothing);
        expect(find.byKey(_divider), findsNothing);
        expect(answer, isFalse);
      });
    }

    testWidgets('the divider is laid out at dividerExtent', (tester) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        const AdaptiveSplitView(
          primary: SizedBox.expand(key: _primary),
          secondary: SizedBox.expand(key: _secondary),
          // Asks for 40; the view gives it the default hairline.
          divider: SizedBox(key: _divider, width: 40),
        ),
      );

      expect(_rectOf(tester, _divider), const Rect.fromLTRB(400, 0, 401, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(401, 0, 1000, 800),
      );
    });

    testWidgets('the divider sits between the panes', (tester) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(withDivider: true),
      );

      expect(_rectOf(tester, _primary), const Rect.fromLTRB(0, 0, 400, 800));
      expect(_rectOf(tester, _divider), const Rect.fromLTRB(400, 0, 402, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(402, 0, 1000, 800),
      );
    });

    testWidgets('no secondary: the placeholder fills its pane', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(withSecondary: false, withPlaceholder: true),
      );

      expect(
        _rectOf(tester, _placeholder),
        const Rect.fromLTRB(400, 0, 1000, 800),
      );
    });

    testWidgets('no secondary and no placeholder: primary keeps its width', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(withSecondary: false),
      );

      expect(_rectOf(tester, _primary).width, 400);
    });

    testWidgets('the placeholder is not shown in a single pane', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(700, 800),
        _splitView(withSecondary: false, withPlaceholder: true),
      );

      expect(find.byKey(_placeholder), findsNothing);
    });

    testWidgets('RTL puts the primary pane at the start (right) edge', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(),
        textDirection: TextDirection.rtl,
      );

      expect(
        _rectOf(tester, _primary),
        const Rect.fromLTRB(600, 0, 1000, 800),
      );
      expect(_rectOf(tester, _secondary), const Rect.fromLTRB(0, 0, 600, 800));
    });
  });

  group('at a vertical fold or hinge (book)', () {
    testWidgets('splits exactly at a hinge, even on a compact window', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(580, 800),
        _splitView(withDivider: true),
        displayFeatures: [_hinge],
      );

      // Nothing under the hinge (280..300), and no divider either.
      expect(_rectOf(tester, _primary), const Rect.fromLTRB(0, 0, 280, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(300, 0, 580, 800),
      );
      expect(find.byKey(_divider), findsNothing);
    });

    testWidgets('RTL: the primary pane is the part right of the hinge', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(580, 800),
        _splitView(),
        displayFeatures: [_hinge],
        textDirection: TextDirection.rtl,
      );

      expect(
        _rectOf(tester, _primary),
        const Rect.fromLTRB(300, 0, 580, 800),
      );
      expect(_rectOf(tester, _secondary), const Rect.fromLTRB(0, 0, 280, 800));
    });

    testWidgets('splits at a half-opened fold on a medium window', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(700, 800),
        _splitView(),
        displayFeatures: [_halfOpenedFold(const Rect.fromLTWH(350, 0, 0, 800))],
      );

      expect(_rectOf(tester, _primary), const Rect.fromLTRB(0, 0, 350, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(350, 0, 700, 800),
      );
    });

    testWidgets('a fold opened flat is ignored', (tester) async {
      DisplayFeature flatFold(double x) => DisplayFeature(
        bounds: Rect.fromLTWH(x, 0, 0, 800),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      );

      // Medium: one pane, as if there were no fold.
      await _pumpAt(
        tester,
        const Size(700, 800),
        _splitView(),
        displayFeatures: [flatFold(350)],
      );
      expect(find.byKey(_secondary), findsNothing);

      // Expanded: split at the fraction (400), not at the fold (500).
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(),
        displayFeatures: [flatFold(500)],
      );
      expect(_rectOf(tester, _primary).width, 400);
    });

    testWidgets('a fold at the view\'s edge is ignored', (tester) async {
      // Nothing would be left on one side of it: the window class decides.
      await _pumpAt(
        tester,
        const Size(1000, 800),
        _splitView(),
        displayFeatures: [
          _halfOpenedFold(const Rect.fromLTWH(1000, 0, 0, 800)),
        ],
      );

      expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 400, 800));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(400, 0, 1000, 800),
      );
    });

    testWidgets('a cutout is ignored', (tester) async {
      await _pumpAt(
        tester,
        const Size(580, 800),
        _splitView(),
        displayFeatures: [
          const DisplayFeature(
            bounds: Rect.fromLTRB(270, 0, 310, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ],
      );

      expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 580, 800));
      expect(find.byKey(_secondary), findsNothing);
    });

    testWidgets('a view narrower than the window cannot place the fold, so '
        'ignores it', (tester) async {
      // Beside an 80-wide rail: the fold at x=350 cannot be mapped into
      // the view, so the medium window decides — one pane.
      await _pumpAt(
        tester,
        const Size(700, 800),
        Padding(padding: const EdgeInsets.only(left: 80), child: _splitView()),
        displayFeatures: [_halfOpenedFold(const Rect.fromLTWH(350, 0, 0, 800))],
      );

      expect(
        _rectOf(tester, _primary),
        const Rect.fromLTRB(80, 0, 700, 800),
      );
      expect(find.byKey(_secondary), findsNothing);
    });
  });

  group('at a horizontal fold (tabletop)', () {
    final tabletop = _halfOpenedFold(const Rect.fromLTWH(0, 370, 720, 0));

    testWidgets('stacks primary above the fold, secondary below', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Size(720, 740),
        _splitView(withDivider: true),
        displayFeatures: [tabletop],
      );

      expect(_rectOf(tester, _primary), const Rect.fromLTRB(0, 0, 720, 370));
      expect(
        _rectOf(tester, _secondary),
        const Rect.fromLTRB(0, 370, 720, 740),
      );
      expect(find.byKey(_divider), findsNothing);
    });

    testWidgets('tabletopSplit: false treats it as no fold at all', (
      tester,
    ) async {
      // Medium window: one pane.
      await _pumpAt(
        tester,
        const Size(720, 740),
        _splitView(tabletopSplit: false),
        displayFeatures: [tabletop],
      );
      expect(_rectOf(tester, _primary), const Rect.fromLTWH(0, 0, 720, 740));
      expect(find.byKey(_secondary), findsNothing);

      // Expanded window: side by side, as the window class says.
      await _pumpAt(
        tester,
        const Size(1000, 740),
        _splitView(tabletopSplit: false),
        displayFeatures: [
          _halfOpenedFold(const Rect.fromLTWH(0, 370, 1000, 0)),
        ],
      );
      expect(_rectOf(tester, _primary), const Rect.fromLTRB(0, 0, 400, 740));
    });

    testWidgets('a view shorter than the window ignores it', (tester) async {
      await _pumpAt(
        tester,
        const Size(720, 740),
        Padding(padding: const EdgeInsets.only(top: 56), child: _splitView()),
        displayFeatures: [tabletop],
      );

      expect(find.byKey(_secondary), findsNothing);
    });
  });

  group('AdaptiveSplitView.isSplit', () {
    testWidgets('reports what the view above decided', (tester) async {
      late bool answer;
      AdaptiveSplitView view() => _splitView(
        primary: Builder(
          builder: (context) {
            answer = AdaptiveSplitView.isSplit(context);
            return const SizedBox.expand();
          },
        ),
      );

      await _pumpAt(tester, const Size(700, 800), view());
      expect(answer, isFalse);

      await _pumpAt(tester, const Size(1000, 800), view());
      expect(answer, isTrue);

      // Compact, but split at the hinge: the answer follows the view, not
      // the window class.
      await _pumpAt(
        tester,
        const Size(580, 800),
        view(),
        displayFeatures: [_hinge],
      );
      expect(answer, isTrue);
    });

    testWidgets('is false with no split view above', (tester) async {
      late bool answer;
      await _pumpAt(
        tester,
        const Size(1000, 800),
        Builder(
          builder: (context) {
            answer = AdaptiveSplitView.isSplit(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(answer, isFalse);
    });
  });

  testWidgets('the primary pane keeps its state across every layout', (
    tester,
  ) async {
    _Probe.created.clear();
    final view = _splitView(primary: const _Probe());

    // One pane -> side by side -> at a book fold -> stacked at a tabletop
    // fold: a rotation, a resize and an unfolding, one after the other.
    await _pumpAt(tester, const Size(700, 800), view);
    expect(_rectOf(tester, _primary).width, 700);

    await _pumpAt(tester, const Size(1000, 800), view);
    expect(_rectOf(tester, _primary).width, 400);

    await _pumpAt(
      tester,
      const Size(1000, 800),
      view,
      displayFeatures: [_halfOpenedFold(const Rect.fromLTWH(500, 0, 0, 800))],
    );
    expect(_rectOf(tester, _primary).width, 500);

    await _pumpAt(
      tester,
      const Size(1000, 800),
      view,
      displayFeatures: [_halfOpenedFold(const Rect.fromLTWH(0, 400, 1000, 0))],
    );
    expect(_rectOf(tester, _primary).height, 400);

    expect(_Probe.created, hasLength(1));
  });
}
