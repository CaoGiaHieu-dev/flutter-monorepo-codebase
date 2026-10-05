import 'dart:math' as math;

import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The shipped palette's pairs a screen actually draws, held to WCAG 2.x AA:
/// 4.5:1 for text, 3:1 for the boundary of a control (1.4.3, 1.4.11). A token
/// edit that breaks one of these fails here instead of in a user's eyes.
void main() {
  final palettes = {
    'light': ThemeSystemExtension.light,
    'dark': ThemeSystemExtension.dark,
  };

  for (final MapEntry(key: name, value: p) in palettes.entries) {
    group('$name palette', () {
      test('body text reads on the page and on a card', () {
        expect(_contrast(p.textPrimary, p.background), greaterThanOrEqualTo(7));
        expect(_contrast(p.textPrimary, p.surface), greaterThanOrEqualTo(7));
        expect(
          _contrast(p.textSecondary, p.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(p.textSecondary, p.background),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('textInverse reads on every fill that takes it (onPrimary, the '
          'gradients, filled buttons)', () {
        for (final fill in [
          p.primary,
          p.primaryContainer,
          p.info,
          p.error,
          ...p.primaryGradientColors,
        ]) {
          expect(
            _contrast(p.textInverse, fill),
            greaterThanOrEqualTo(4.5),
            reason: '${fill.toARGB32().toRadixString(16)} under textInverse',
          );
        }
      });

      test('an error line reads on a field and on the page', () {
        expect(_contrast(p.error, p.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(p.error, p.background), greaterThanOrEqualTo(4.5));
      });

      test('a field boundary, its focus ring and its error ring are 3:1', () {
        // CustomInputField: textSecondary at rest, primary focused, error
        // when invalid — on the surface the field is filled with.
        for (final boundary in [p.textSecondary, p.primary, p.error]) {
          expect(_contrast(boundary, p.surface), greaterThanOrEqualTo(3));
          expect(_contrast(boundary, p.background), greaterThanOrEqualTo(3));
        }
      });

      test('a disabled button label is still legible on its fill', () {
        expect(_contrast(p.textSecondary, p.surfaceVariant), greaterThan(4));
      });
    });
  }
}
