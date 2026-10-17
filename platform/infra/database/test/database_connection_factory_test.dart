import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:core_database/src/connection/native_connection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backgroundExecutorFor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('core_database_pool');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    // `MigrationStrategy.beforeOpen` runs on the writer only. A `SELECT`
    // outside a transaction is served by the read pool, so this reads the
    // reader's own setting — `0` before the factory configured every
    // connection, which made a reader fail at once on any lock.
    test('gives read-pool connections a busy timeout', () async {
      final database = TestDatabase(
        backgroundExecutorFor(
          File(p.join(tempDir.path, 'pool.sqlite')),
          readPool: 1,
        ),
      );
      addTearDown(database.close);

      final row = await database
          .customSelect('PRAGMA busy_timeout')
          .getSingle();

      expect(row.data.values.first, DatabaseConstants.BUSY_TIMEOUT_MS);
    });
  });

  group('the database directory', () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory support;
    late Directory documents;

    setUp(() {
      support = Directory.systemTemp.createTempSync('core_database_support');
      documents = Directory.systemTemp.createTempSync('core_database_docs');
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => switch (call.method) {
          'getApplicationSupportDirectory' => support.path,
          'getApplicationDocumentsDirectory' => documents.path,
          _ => throw MissingPluginException(call.method),
        },
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(pathProvider, null);
      support.deleteSync(recursive: true);
      documents.deleteSync(recursive: true);
    });

    // On Windows and Linux "documents" is the user's shared ~/Documents.
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      test(
        '${platform.name} keeps it in the application-support directory',
        () async {
          debugDefaultTargetPlatformOverride = platform;

          final file = await resolveDatabaseFile('app.sqlite');

          expect(file.path, p.join(support.path, 'app.sqlite'));
        },
      );
    }

    // Where every shipped mobile install already keeps it: nothing moves.
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      test('${platform.name} keeps it in the documents directory', () async {
        debugDefaultTargetPlatformOverride = platform;

        final file = await resolveDatabaseFile('app.sqlite');

        expect(file.path, p.join(documents.path, 'app.sqlite'));
      });
    }

    test('quarantine is false when there is no file to move', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      expect(await quarantine('app.sqlite'), isFalse);
      expect(
        await DatabaseConnectionFactory.quarantineDatabaseFile(
          fileName: 'app.sqlite',
        ),
        isFalse,
      );
    });

    test('quarantine moves the file and its sidecars aside', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      String at(String name) => p.join(support.path, name);
      for (final name in ['app.sqlite', 'app.sqlite-wal', 'app.sqlite-shm']) {
        File(at(name)).writeAsStringSync(name);
      }

      expect(await quarantine('app.sqlite'), isTrue);

      for (final suffix in ['', '-wal', '-shm']) {
        expect(File(at('app.sqlite$suffix')).existsSync(), isFalse);
        final moved = File(
          at('app.sqlite${DatabaseConstants.CORRUPT_FILE_SUFFIX}$suffix'),
        );
        expect(moved.readAsStringSync(), 'app.sqlite$suffix');
      }
    });
  });
}
