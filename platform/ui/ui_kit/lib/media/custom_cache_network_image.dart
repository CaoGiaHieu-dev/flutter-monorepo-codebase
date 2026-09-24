import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// A cached network image with a spinner while loading and an error icon on
/// failure.
///
/// ## Decode size
///
/// A photo is decoded at its full resolution unless told otherwise — a
/// 4000×3000 JPEG shown in a 48 px avatar still costs ~48 MB of memory.
/// When [width] and/or [height] are given, the image is decoded at that
/// layout size times the device pixel ratio instead (see
/// [resolveMemCacheSize] for which side is used for which [fit]). Pass
/// [memCacheWidth] / [memCacheHeight] to choose the decode size yourself;
/// either one given switches the derivation off.
///
/// ## Semantics
///
/// [semanticLabel] describes the image to screen readers. Leave it `null`
/// for a purely decorative image.
///
/// Sizes arrive already scaled (`context.w(48)`), like every `core_ui_kit`
/// widget's; the widget does not scale them again.
class CustomCacheNetworkImage extends StatelessWidget {
  const CustomCacheNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.memCacheHeight,
    this.semanticLabel,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Width, in physical pixels, to decode the image at. See the class docs.
  final int? memCacheWidth;

  /// Height, in physical pixels, to decode the image at. See the class docs.
  final int? memCacheHeight;

  /// What the image shows, for screen readers.
  final String? semanticLabel;

  /// The decode size for a [width] × [height] layout box drawn with [fit]
  /// on a screen of [devicePixelRatio].
  ///
  /// Only ever sets both sides for [BoxFit.fill]: `ResizeImage` with both
  /// sides stretches to exactly that size, which is what `fill` draws
  /// anyway, and would distort any other fit. Otherwise one side is set and
  /// the other follows the image's own aspect ratio:
  ///
  /// - one side known → that side;
  /// - both known, [BoxFit.fitHeight] → the height;
  /// - both known, [BoxFit.contain] / [BoxFit.scaleDown] /
  ///   [BoxFit.fitWidth] → the width, which the drawn image never exceeds;
  /// - both known, [BoxFit.cover] → nothing: the side cover fills depends
  ///   on the image's aspect ratio, unknown before decoding, and guessing
  ///   wrong decodes too small and draws blurry. Pass the size explicitly;
  /// - [BoxFit.none] → nothing: the image is drawn at its own size.
  ///
  /// A side that is not a positive finite number (e.g. `double.infinity`)
  /// counts as unknown.
  @visibleForTesting
  static ({int? width, int? height}) resolveMemCacheSize({
    required double? width,
    required double? height,
    required BoxFit fit,
    required double devicePixelRatio,
  }) {
    int? toPixels(double? logical) {
      if (logical == null || !logical.isFinite || logical <= 0) return null;
      return (logical * devicePixelRatio).ceil();
    }

    final w = toPixels(width);
    final h = toPixels(height);
    if (fit == BoxFit.none || (w == null && h == null)) {
      return (width: null, height: null);
    }
    if (w == null) return (width: null, height: h);
    if (h == null) return (width: w, height: null);
    return switch (fit) {
      BoxFit.fill => (width: w, height: h),
      BoxFit.fitHeight => (width: null, height: h),
      BoxFit.cover || BoxFit.none => (width: null, height: null),
      BoxFit.contain ||
      BoxFit.scaleDown ||
      BoxFit.fitWidth => (width: w, height: null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (url.isEmpty) {
      image = const Center(child: Icon(Icons.error));
    } else {
      final explicit = memCacheWidth != null || memCacheHeight != null;
      final derived = explicit
          ? (width: memCacheWidth, height: memCacheHeight)
          : resolveMemCacheSize(
              width: width,
              height: height,
              fit: fit,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            );
      image = CachedNetworkImage(
        imageUrl: url,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor,
            ),
          ),
        ),
        errorBuilder: (context, url, error) =>
            const Center(child: Icon(Icons.error)),
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: derived.width,
        memCacheHeight: derived.height,
      );
    }

    final label = semanticLabel;
    if (label == null) return image;
    // One node for the image, whatever state it is in: the spinner and the
    // error icon underneath would otherwise be read out instead.
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(child: image),
    );
  }
}
