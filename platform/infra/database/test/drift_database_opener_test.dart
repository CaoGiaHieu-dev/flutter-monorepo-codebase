import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriftDatabaseOpener.open — corruption recovery', () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory dir;
    late List<String> logged;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('core_database_opener');
      messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
      logged = [];
      DynamicLogger.configure(
        logHandler: (
          message, {
          error,
          level = 0,
          name = '',
          sequenceNumber,
          stackTrace,
          time,
          zone,
        }) => logged.add(message),
      );
    });

    tearDown(() {
      DynamicLogger.reset();
      messenger.setMockMethodCallHandler(pathProvider, null);
      dir.deleteSync(recursive: true);
    });

    test(
      'a corrupt file is moved aside and the database reopened empty',
      () async {
        final file = File(p.join(dir.path, 'x.sqlite'))
          ..writeAsStringSync('not a database ' * 300);

        final database = await DriftDatabaseOpener.open(
          TestDatabase.new,
          fileName: 'x.sqlite',
        );
        addTearDown(database.close);

        expect(
          File('${file.path}${DatabaseConstants.CORRUPT_FILE_SUFFIX}')
              .existsSync(),
          isTrue,
        );
        // The logger quotes the message as JSON: `"` reads `\"` there.
        expect(logged.single, contains('quarantined as'));
        expect(logged.single, contains('recreated empty'));
      },
    );

    // What the web always gets: `quarantineDatabaseFile` moves nothing
    // there. Reproduced natively with no file on disk — the builder fails
    // before the lazy executor ever creates one.
    test('when nothing could be moved, the error stands: no reopen and no '
        'claim that data was lost', () async {
      var builds = 0;
      Future<TestDatabase> open() => DriftDatabaseOpener.open((executor) {
        builds++;
        throw StateError('file is not a database');
      }, fileName: 'gone.sqlite');

      await expectLater(open(), throwsA(isA<StateError>()));

      expect(builds, 1, reason: 'the same database is not opened twice');
      expect(logged.single, contains('no file to move aside'));
      expect(logged.single, isNot(contains('Stored data is lost')));
    });
  });

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
        DriftDatabaseOpener.isCorruptionError(
          Exception('some unrelated failure'),
        ),
        isFalse,
      );
    });
  });
}
