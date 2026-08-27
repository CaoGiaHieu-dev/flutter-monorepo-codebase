import 'dart:ui' as ui;

import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class TextScaleDown extends StatelessWidget {
  const TextScaleDown(
    this.text, {
    super.key,
    this.alignment = Alignment.centerLeft,
    this.textSpan,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String? text;
  final AlignmentGeometry alignment;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final ui.TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        text ?? '',
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      ),
    );
  }
}

// ==========================================
// 🛠️ Interactive Previews (Flutter 3.44+)
// ==========================================

@Preview(name: 'Default', group: 'Text Scale Down')
Widget textScaleDownPreview() {
  return Builder(
    builder: (context) {
      return Center(
        child: Container(
          color: Colors.blue.shade100,
          width: 100, // Small width to force scaling down
          child: TextScaleDown(
            'This is a very long text that will scale down to fit the small container.',
            style: AppTextStyles.bodyLargeStyle(context),
          ),
        ),
      );
    },
  );
}
