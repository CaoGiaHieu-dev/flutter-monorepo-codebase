import 'platform_facts.dart';

/// A window size class — the Material 3 width classes `core_responsive` calls
/// `WindowSizeClass`, spelled here because the kernel is pure Dart.
///
/// `profile_defaults_test.dart` in `platform_app_shell` keeps the two equal
/// by name and order, so a class added on one side fails a test on the other.
enum WindowClass {
  /// Under 600 dp: phones in portrait, a flip phone, a narrow split pane.
  compact,

  /// 600–839 dp: small tablets and foldables in portrait.
  medium,

  /// 840–1199 dp: tablets in landscape, an unfolded foldable, small desktops.
  expanded,

  /// 1200–1599 dp: large tablets in landscape, desktop windows.
  large,

  /// 1600 dp and wider.
  extraLarge,
}

/// How the shell scales design values (`context.w`, `context.h`, `context.sp`)
/// in one [WindowClass].
///
/// A class the app does not list in [DisplayProfile.scale] keeps
/// [ScalePolicy.downOnly].
sealed class ScalePolicy {
  const ScalePolicy();

  /// No scaling in either direction: a value is drawn at its design size.
  ///
  /// For a class whose layout is built to real logical pixels — a desktop
  /// window — where tracking the window would only fight the layout.
  const factory ScalePolicy.fixed() = FixedScale;

  /// Shrink below the design size, never grow past it: a window smaller than
  /// the artboard scales the design down to fit, a larger one draws it 1:1.
  const factory ScalePolicy.downOnly() = DownOnlyScale;

  /// Like [ScalePolicy.downOnly], but allowed to grow: layout factors up to
  /// [max] and the text factor up to [textMax].
  ///
  /// A null [max] stays at 1 (no growth); a null [textMax] follows [max].
  const factory ScalePolicy.bounded({double? max, double? textMax}) =
      BoundedScale;
}

/// [ScalePolicy.fixed].
final class FixedScale extends ScalePolicy {
  const FixedScale();
}

/// [ScalePolicy.downOnly].
final class DownOnlyScale extends ScalePolicy {
  const DownOnlyScale();
}

/// [ScalePolicy.bounded].
final class BoundedScale extends ScalePolicy {
  const BoundedScale({this.max, this.textMax})
    : assert(max == null || max > 0, 'max must be a positive factor'),
      assert(
        textMax == null || textMax > 0,
        'textMax must be a positive factor',
      );

  /// The largest factor a layout value may grow to, or null for 1.
  final double? max;

  /// The largest factor the text size may grow to, or null for [max].
  final double? textMax;
}

/// How the shell sizes and scales the UI for this app — the design artboard,
/// the per-window-class scale policy and the OS font-size cap.
///
/// Every default is what the template did before an app could say anything, so
/// an app that sets none behaves exactly as before. An invalid value is a
/// compile error where it is written: a `const DisplayProfile(textScaleMax:
/// 1.5)` fails `flutter analyze` with `const_eval_throws_exception`.
final class DisplayProfile {
  const DisplayProfile({
    this.designSize = const SizeSpec(375, 812),
    this.textScaleMax = 2.0,
    this.splitScreenMode = true,
    this.scale = const {WindowClass.expanded: ScalePolicy.fixed()},
    this.phoneMaxShortestSide = 600,
  }) : assert(
         textScaleMax >= 2.0 && textScaleMax <= 4.0,
         'the OS font size is honoured up to at least 200 %, and at most 400 %',
       ),
       assert(
         phoneMaxShortestSide >= 300 && phoneMaxShortestSide <= 1200,
         'the phone threshold is a shortest side between 300 and 1200 dp',
       );

  /// The artboard the design is drawn at, in logical pixels (a `SizeSpec` is
  /// always positive). Default: the 375 × 812 phone artboard.
  final SizeSpec designSize;

  /// The largest OS text scale the app honours (`MediaQuery` text scaling is
  /// clamped to it). Default 2.0 — the "resize text up to 200 %" of WCAG 2.2
  /// SC 1.4.4. Range 2.0–4.0: an app may allow more, never less, because the
  /// user's font size is an accessibility setting.
  final double textScaleMax;

  /// Keeps height scaling sane when the app is a short split-screen pane.
  /// Default on.
  final bool splitScreenMode;

  /// The scale policy of each window class listed. Default: tablets in
  /// landscape, unfolded foldables and desktop windows (`expanded`) are laid
  /// out in real logical pixels ([ScalePolicy.fixed]); every class not listed
  /// is [ScalePolicy.downOnly].
  final Map<WindowClass, ScalePolicy> scale;

  /// A display whose shortest side is below this is a phone for
  /// `OrientationPolicy.phonesPortrait`. Default 600 dp, the Material 3
  /// `medium` breakpoint. Range 300–1200.
  final double phoneMaxShortestSide;
}
