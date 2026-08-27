import 'package:core_database/core_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftDatabaseOpener.isCorruptionError', () {
    // This predicate decides whether a user's database file may be moved
    // aside, so it is asserted directly rather than only through a real
    // corrupt file.

    test('recognises corrupt-file errors', () {
      for (final marker in DatabaseConstants.CORRUPTION_ERROR_MARKERS) {
        expect(
          DriftDatabaseOpener.isCorruptionError(
            Exception('SqliteException: $marker'),
          ),
          isTrue,
          reason: 'expected "$marker" to be treated as corruption',
        );
      }
    });

    test('is case-insensitive', () {
      expect(
        DriftDatabaseOpener.isCorruptionError(
          Exception('DATABASE DISK IMAGE IS MALFORMED'),
        ),
        isTrue,
      );
    });

    test('never recovers from environment failures', () {
      for (final marker in DatabaseConstants.ENVIRONMENT_ERROR_MARKERS) {
        expect(
          DriftDatabaseOpener.isCorruptionError(
            Exception('SqliteException: $marker'),
          ),
          isFalse,
          reason: 'expected "$marker" to be left untouched',
        );
      }
    });

    test('an environment marker vetoes a corruption match', () {
      // Both markers present: recovery must lose. Deleting data that was
      // never corrupt is worse than surfacing a startup error.
      expect(
        DriftDatabaseOpener.isCorruptionError(
          Exception(
            'SqliteException: database disk image is malformed; '
            'disk i/o error',
          ),
        ),
        isFalse,
      );
    });

    test('ignores unrelated errors', () {
      expect(
        DriftDatabaseOpener.isCorruptionError(Exception('some unrelated failure')),
        isFalse,
      );
    });
  });
}
