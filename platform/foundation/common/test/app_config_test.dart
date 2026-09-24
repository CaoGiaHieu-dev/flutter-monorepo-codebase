import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flavor resolution decides whether TLS certificate validation may be
/// switched off, so every fallback is pinned down here.
void main() {
  group('AppConfig.parseFlavor', () {
    test('recognises every flavor, case-insensitively', () {
      expect(AppConfig.parseFlavor('dev'), Flavor.dev);
      expect(AppConfig.parseFlavor('Staging'), Flavor.staging);
      expect(AppConfig.parseFlavor(' PROD '), Flavor.prod);
    });

    test('returns null for a missing, empty or unknown flavor', () {
      expect(AppConfig.parseFlavor(null), isNull);
      expect(AppConfig.parseFlavor(''), isNull);
      expect(AppConfig.parseFlavor('develop'), isNull);
      expect(AppConfig.parseFlavor('production'), isNull);
    });
  });

  group('AppConfig.resolveFlavor', () {
    test('a declared flavor wins in every build mode', () {
      for (final isDebug in [true, false]) {
        expect(
          AppConfig.resolveFlavor('staging', isDebug: isDebug),
          Flavor.staging,
        );
        expect(AppConfig.resolveFlavor('dev', isDebug: isDebug), Flavor.dev);
      }
    });

    test('falls back to dev only in a debug build', () {
      expect(AppConfig.resolveFlavor(null, isDebug: true), Flavor.dev);
      expect(AppConfig.resolveFlavor('unknown', isDebug: true), Flavor.dev);
    });

    test('falls back to prod in a profile or release build', () {
      expect(AppConfig.resolveFlavor(null, isDebug: false), Flavor.prod);
      expect(AppConfig.resolveFlavor('unknown', isDebug: false), Flavor.prod);
    });
  });

  group('AppConfig.allowsCertificateBypass', () {
    test('only a debug build that declared dev may bypass', () {
      expect(
        AppConfig.allowsCertificateBypass(
          declaredFlavor: Flavor.dev,
          isDebug: true,
        ),
        isTrue,
      );
    });

    test('never in a profile or release build, even for dev', () {
      expect(
        AppConfig.allowsCertificateBypass(
          declaredFlavor: Flavor.dev,
          isDebug: false,
        ),
        isFalse,
      );
    });

    test('a missing or unknown flavor is treated as prod', () {
      expect(
        AppConfig.allowsCertificateBypass(
          declaredFlavor: AppConfig.parseFlavor(null),
          isDebug: true,
        ),
        isFalse,
      );
      expect(
        AppConfig.allowsCertificateBypass(
          declaredFlavor: AppConfig.parseFlavor('qa'),
          isDebug: true,
        ),
        isFalse,
      );
    });

    test('staging and prod never bypass', () {
      for (final flavor in [Flavor.staging, Flavor.prod]) {
        expect(
          AppConfig.allowsCertificateBypass(
            declaredFlavor: flavor,
            isDebug: true,
          ),
          isFalse,
        );
      }
    });

    test('a test run declares no flavor, so validation stays on', () {
      expect(AppConfig.declaredFlavor, isNull);
      expect(AppConfig.bypassesCertificateValidation, isFalse);
    });
  });
}
