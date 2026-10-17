import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../composer/src/manifest_v2.dart';
import '../composer/src/runners.dart';
import '../shared/toolchain.dart';

/// `composer runners` (`tools/composer/src/runners.dart`): every platform an
/// app declares `runner: scaffold` gets a runner `flutter create` writes in a
/// temporary directory — only `<p>/` is copied in — and, on every run, the
/// fixed patch set: the macOS network-client entitlement, and for an app on
/// the web that links core_database a sha256-checked `sqlite3.wasm` and a
/// compiled `drift_worker.js` (RULE-83). `flutter pub get` runs in the app
/// after a new runner, and on any run that finds a runner without the plugin
/// files it writes; a file whose bytes would not change is never rewritten.
///
/// `flutter`, `dart` and the download are fakes (the `ProcessRunner` and
/// `Fetcher` seams), so nothing is created, compiled or fetched for real.
void main() {
  /// What a fake `flutter create` writes into its target, per platform —
  /// plus what the real one writes beside the platforms, which must never
  /// reach the app.
  const macosEntitlements =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>com.apple.security.app-sandbox</key>\n'
      '\t<true/>\n'
      '\t<key>com.apple.security.cs.allow-jit</key>\n'
      '\t<true/>\n'
      '</dict>\n'
      '</plist>\n';

  /// The bytes the fake release serves, and the hash table naming them.
  final wasm = List<int>.generate(64, (i) => i);
  final wasmSha = sha256.convert(wasm).toString();
  const tag = 'sqlite3-9.9.9';

  late Directory root;
  late Directory cache;
  late List<List<String>> calls;
  late List<String> pubGets;
  late List<List<String>> pubGetArgs;
  late List<String> createTargets;
  late String workerOutput;
  late List<Uri> fetched;
  late List<String> info;
  late List<String> warnings;
  late List<String> errors;

  setUp(() {
    root = Directory.systemTemp.createTempSync('runners_test_');
    cache = Directory(p.join(root.path, '.cache'));
    calls = [];
    pubGets = [];
    pubGetArgs = [];
    createTargets = [];
    workerOutput = '// worker';
    fetched = [];
    info = [];
    warnings = [];
    errors = [];
    // The resolved sqlite3, as pub writes it: a relative rootUri.
    final sqlite = Directory(p.join(root.path, 'pub', 'sqlite3-9.9.9'))
      ..createSync(recursive: true);
    File(p.join(sqlite.path, 'pubspec.yaml')).writeAsStringSync(
      'name: sqlite3\nversion: 9.9.9\n',
    );
    _write(
      root,
      '.dart_tool/package_config.json',
      '{"configVersion": 2, "packages": [{"name": "sqlite3", '
          '"rootUri": "../pub/sqlite3-9.9.9", "packageUri": "lib/"}]}',
    );
    _write(
      root,
      'pub/sqlite3-9.9.9/$kSqliteAssetHashes',
      "const String? releaseTag = '$tag';\n"
          'const Map<String, String> assetNameToSha256Hash = {\n'
          "  'sqlite3.debug.wasm': '${'0' * 64}',\n"
          "  'sqlite3.wasm': '$wasmSha',\n"
          '};\n',
    );
    _write(root, kDriftWorkerSource, 'void main() {}\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// A fake `flutter create`, `flutter pub get` and `dart compile js`
  /// (which writes [workerOutput]). [createExit] fails the create,
  /// [pubGetExit] the pub get. A passing pub get writes, as the real one
  /// does, the [kPubGetRunnerFiles] of every runner folder in the app —
  /// unless [pubGetWrites] is false.
  ProcessRunner fakeRun({
    int createExit = 0,
    int pubGetExit = 0,
    bool pubGetWrites = true,
  }) => (exe, args, {workingDirectory}) async {
    calls.add([exe, ...args]);
    final rest = args.skip(
      exe == flutterExecutable ? flutterArgs.length : dartArgs.length,
    );
    if (rest.first == 'pub') {
      pubGets.add(workingDirectory!);
      pubGetArgs.add(rest.toList());
      if (pubGetExit != 0) return ProcessResult(0, pubGetExit, '', 'x');
      if (pubGetWrites) {
        for (final MapEntry(key: platform, value: file)
            in kPubGetRunnerFiles.entries) {
          if (Directory(p.join(workingDirectory, platform)).existsSync()) {
            _write(Directory(workingDirectory), file, '// $platform');
          }
        }
      }
      return ProcessResult(0, 0, '', '');
    }
    if (rest.first == 'create') {
      if (createExit != 0) {
        return ProcessResult(0, createExit, '', 'boom');
      }
      final target = rest.last;
      createTargets.add(target);
      final platforms = rest
          .firstWhere((a) => a.startsWith('--platforms='))
          .substring('--platforms='.length)
          .split(',');
      for (final name in platforms) {
        if (name == 'macos') {
          for (final file in kMacosEntitlements) {
            _write(Directory(target), file, macosEntitlements);
          }
        } else {
          _write(Directory(target), '$name/runner.txt', name);
        }
      }
      _write(Directory(target), 'test/widget_test.dart', 'MyApp();\n');
      _write(Directory(target), 'analysis_options.yaml', 'lints\n');
      _write(Directory(target), 'pubspec.yaml', 'name: x\n');
      return ProcessResult(0, 0, '', '');
    }
    if (rest.first == 'compile') {
      final out = rest.toList()[rest.toList().indexOf('-o') + 1];
      final file = p.join(workingDirectory!, out);
      File(file)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(workerOutput);
      File('$file.deps').writeAsStringSync('deps');
      File('$file.map').writeAsStringSync('map');
      return ProcessResult(0, 0, '', '');
    }
    return ProcessResult(0, 64, '', 'unexpected');
  };

  Fetcher fakeFetch([List<int>? bytes]) => (url) async {
    fetched.add(url);
    return bytes ?? wasm;
  };

  RunnerApp app({
    Map<String, String> platforms = const {'web': 'scaffold'},
    bool database = false,
    String org = 'com.acme',
  }) => RunnerApp(
    id: 'demo',
    dir: p.join(root.path, 'apps', 'demo'),
    pubspecName: 'demo_app',
    linksDatabase: database,
    decl: AppDeclaration(
      name: 'Demo',
      org: org,
      entrypoint: 'lib/main.dart',
      flavors: const {},
      env: const [],
      platforms: [
        for (final entry in platforms.entries)
          PlatformDecl(entry.key, entry.value, null),
      ],
      capabilities: const {},
    ),
  );

  Future<int> generate(
    List<RunnerApp> apps, {
    RunnersRequest request = const RunnersRequest(),
    ProcessRunner? run,
    Fetcher? fetch,
  }) => generateRunners(
    root: root.path,
    apps: apps,
    request: request,
    run: run ?? fakeRun(),
    fetch: fetch ?? fakeFetch(),
    environment: {
      'XDG_CACHE_HOME': cache.path,
      'LOCALAPPDATA': cache.path,
      'HOME': root.path,
    },
    out: info.add,
    warn: warnings.add,
    err: errors.add,
  );

  String appFile(String rel) => p.join(root.path, 'apps', 'demo', rel);

  test('flutter create gets --no-pub, the platforms, app.org and the pubspec '
      'name, and writes into a temporary directory', () async {
    final code = await generate([
      app(platforms: {'web': 'scaffold', 'linux': 'scaffold'}),
    ]);

    expect(code, 0, reason: errors.join('\n'));
    expect(calls, hasLength(2));
    final create = calls.first;
    expect(create.first, flutterExecutable);
    final args = create.skip(1 + flutterArgs.length).toList();
    expect(args, [
      'create',
      '--no-pub',
      '--platforms=web,linux',
      '--org',
      'com.acme',
      '--project-name',
      'demo_app',
      createTargets.single,
    ]);
    // <tmp>/<pubspec name>, outside the repository, gone afterwards.
    final target = createTargets.single;
    expect(p.basename(target), 'demo_app');
    expect(p.isWithin(Directory.systemTemp.path, target), isTrue);
    expect(p.isWithin(root.path, target), isFalse);
    expect(Directory(p.dirname(target)).existsSync(), isFalse);
  });

  test('only <p>/ is copied: nothing else flutter create writes reaches the '
      'app', () async {
    final code = await generate([
      app(platforms: {'web': 'scaffold', 'linux': 'scaffold'}),
    ]);

    expect(code, 0, reason: errors.join('\n'));
    expect(File(appFile('web/runner.txt')).existsSync(), isTrue);
    expect(File(appFile('linux/runner.txt')).existsSync(), isTrue);
    expect(File(appFile('test/widget_test.dart')).existsSync(), isFalse);
    expect(File(appFile('analysis_options.yaml')).existsSync(), isFalse);
    expect(File(appFile('pubspec.yaml')).existsSync(), isFalse);
  });

  test('the macOS network-client entitlement is added once; a second run '
      'changes nothing', () async {
    final macos = app(platforms: {'macos': 'scaffold'});
    expect(await generate([macos]), 0, reason: errors.join('\n'));

    for (final file in kMacosEntitlements) {
      final text = File(appFile(file)).readAsStringSync();
      expect(
        text,
        contains(
          '\t<key>com.apple.security.app-sandbox</key>\n'
          '\t<true/>\n'
          '\t<key>com.apple.security.network.client</key>\n'
          '\t<true/>\n',
        ),
      );
    }
    final first = {
      for (final f in kMacosEntitlements)
        f: File(appFile(f)).readAsStringSync(),
    };

    expect(await generate([macos]), 0);
    for (final f in kMacosEntitlements) {
      expect(File(appFile(f)).readAsStringSync(), first[f]);
      expect(
        '<key>com.apple.security.network.client</key>'
            .allMatches(first[f]!)
            .length,
        1,
      );
    }
    // The folder existed the second time: no second flutter create, and no
    // second pub get.
    expect(calls, hasLength(2));
    expect(info.last, '  apps/demo: up to date (macos) — nothing written');
  });

  test('an entitlements file without the sandbox anchor is an error naming '
      'the file', () async {
    final macos = app(platforms: {'macos': 'scaffold'});
    _write(
      root,
      'apps/demo/macos/Runner/DebugProfile.entitlements',
      '<plist><dict></dict></plist>\n',
    );
    _write(
      root,
      'apps/demo/macos/Runner/Release.entitlements',
      macosEntitlements,
    );

    expect(await generate([macos]), 1);
    expect(
      errors.join('\n'),
      contains('apps/demo/macos/Runner/DebugProfile.entitlements'),
    );
    expect(errors.join('\n'), contains('com.apple.security.app-sandbox'));
  });

  test('the wasm tag and hash come from the resolved sqlite3, and the '
      'download is copied into web/ with the worker beside it', () async {
    final code = await generate([app(database: true)]);

    expect(code, 0, reason: errors.join('\n'));
    expect(fetched, [
      Uri.parse(
        'https://github.com/simolus3/sqlite3.dart/releases/download/'
        '$tag/sqlite3.wasm',
      ),
    ]);
    expect(File(appFile('web/sqlite3.wasm')).readAsBytesSync(), wasm);
    // Cached per tag, so the next app (or run) downloads nothing.
    expect(
      File(
        p.join(cache.path, 'flutter_monorepo', 'sqlite3', tag, 'sqlite3.wasm'),
      ).existsSync(),
      isTrue,
    );
    // The worker: dart compile js -O4 from the repository root into a
    // temporary directory; only drift_worker.js reaches web/.
    final compile = calls.last.skip(1 + dartArgs.length).toList();
    expect(compile, [
      'compile',
      'js',
      '-O4',
      '-o',
      compile[4],
      kDriftWorkerSource,
    ]);
    expect(p.basename(compile[4]), 'drift_worker.js');
    expect(p.isWithin(root.path, compile[4]), isFalse);
    expect(File(compile[4]).existsSync(), isFalse);
    expect(
      File(appFile('web/drift_worker.js')).readAsStringSync(),
      '// worker',
    );
    expect(File(appFile('web/drift_worker.js.deps')).existsSync(), isFalse);
    expect(File(appFile('web/drift_worker.js.map')).existsSync(), isFalse);

    // A second run downloads nothing: the cache is checked and reused.
    fetched.clear();
    expect(await generate([app(database: true)]), 0);
    expect(fetched, isEmpty);
  });

  test('an app that does not link core_database gets no web assets', () async {
    expect(await generate([app()]), 0, reason: errors.join('\n'));
    expect(fetched, isEmpty);
    expect(File(appFile('web/sqlite3.wasm')).existsSync(), isFalse);
    expect(calls.where((c) => c.contains('compile')), isEmpty);
  });

  test('parseAssetHashes reads the tag and the sqlite3.wasm hash, and '
      'nothing else', () {
    final parsed = parseAssetHashes(
      "const String? releaseTag = 'sqlite3-3.7.1';\n"
      "  'sqlite3.debug.wasm': '${'a' * 64}',\n"
      "  'sqlite3.wasm': '${'B' * 64}',\n",
    );
    expect(parsed?.tag, 'sqlite3-3.7.1');
    expect(parsed?.sha256, 'b' * 64);
    expect(parseAssetHashes("const releaseTag = 'x';\n"), isNull);
  });

  test('a hash table that moved is an error that says what to do', () async {
    File(
      p.join(root.path, 'pub/sqlite3-9.9.9', kSqliteAssetHashes),
    ).deleteSync();

    expect(await generate([app(database: true)]), 1);
    expect(
      errors.join('\n'),
      contains(
        'sqlite3 9.9.9 ships no asset hash table at $kSqliteAssetHashes — '
        'place a matching sqlite3.wasm in apps/demo/web/ by hand',
      ),
    );
  });

  test('with no hash table, a sqlite3.wasm placed by hand is used and named '
      'unverified: the run exits 0', () async {
    File(
      p.join(root.path, 'pub/sqlite3-9.9.9', kSqliteAssetHashes),
    ).deleteSync();
    _write(root, 'apps/demo/web/sqlite3.wasm', 'placed by hand');

    expect(await generate([app(database: true)]), 0);
    expect(errors, isEmpty);
    expect(
      warnings.join('\n'),
      contains(
        'apps/demo/web/sqlite3.wasm: not verified — sqlite3 9.9.9 ships no '
        'asset hash table at $kSqliteAssetHashes',
      ),
    );
    expect(fetched, isEmpty);
    expect(
      File(appFile('web/sqlite3.wasm')).readAsStringSync(),
      'placed by hand',
    );
    // The worker is still compiled.
    expect(File(appFile('web/drift_worker.js')).existsSync(), isTrue);
  });

  test('a download whose sha256 differs is refused: nothing in web/ or the '
      'cache, exit 1', () async {
    final code = await generate([
      app(database: true),
    ], fetch: fakeFetch([1, 2, 3]));

    expect(code, 1);
    expect(errors.join('\n'), contains('refused, nothing written'));
    expect(File(appFile('web/sqlite3.wasm')).existsSync(), isFalse);
    expect(
      File(
        p.join(cache.path, 'flutter_monorepo', 'sqlite3', tag, 'sqlite3.wasm'),
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'a cached wasm that no longer matches is deleted, never copied',
    () async {
      final cached = File(
        p.join(cache.path, 'flutter_monorepo', 'sqlite3', tag, 'sqlite3.wasm'),
      )..createSync(recursive: true);
      cached.writeAsBytesSync([9, 9, 9]);

      expect(await generate([app(database: true)]), 1);
      expect(cached.existsSync(), isFalse);
      expect(File(appFile('web/sqlite3.wasm')).existsSync(), isFalse);
    },
  );

  test('offline is a warning, and the run still exits 0', () async {
    for (final failure in <Object>[
      const SocketException('no route'),
      const HandshakeException('tls'),
      const HttpException('HTTP 404'),
    ]) {
      warnings.clear();
      final code = await generate([
        app(database: true),
      ], fetch: (url) async => throw failure);
      expect(code, 0, reason: '$failure: ${errors.join('\n')}');
      expect(
        warnings.join('\n'),
        contains('web database assets missing'),
        reason: '$failure',
      );
      expect(
        warnings.join('\n'),
        contains(
          '`dart tools/composer/composer.dart runners --app demo '
          '--platform web` online',
        ),
      );
      expect(File(appFile('web/sqlite3.wasm')).existsSync(), isFalse);
    }
  });

  test(
    'a committed platform is refused, and nothing is written into it',
    () async {
      final mobile = app(
        platforms: {'android': 'committed', 'web': 'scaffold'},
      );

      final code = await generate([
        mobile,
      ], request: const RunnersRequest(platforms: ['android']));

      expect(code, 1);
      expect(
        errors.join('\n'),
        contains(
          'apps/demo/android/ is committed — composer never writes into it',
        ),
      );
      expect(calls, isEmpty);
      // Without --platform, a committed runner is simply not selected.
      errors.clear();
      expect(await generate([mobile]), 0, reason: errors.join('\n'));
      expect(calls.first, contains('--platforms=web'));
    },
  );

  test('--force deletes and regenerates the selected runners', () async {
    _write(root, 'apps/demo/web/stale.txt', 'old');

    final code = await generate([
      app(),
    ], request: const RunnersRequest(force: true));

    expect(code, 0, reason: errors.join('\n'));
    expect(calls, hasLength(2));
    expect(pubGets, [p.join(root.path, 'apps', 'demo')]);
    expect(File(appFile('web/stale.txt')).existsSync(), isFalse);
    expect(File(appFile('web/runner.txt')).existsSync(), isTrue);
  });

  test('an existing runner gets only the patch set', () async {
    _write(root, 'apps/demo/web/index.html', 'mine');
    for (final file in kMacosEntitlements) {
      _write(root, 'apps/demo/$file', macosEntitlements);
    }

    final code = await generate([
      app(platforms: {'web': 'scaffold', 'macos': 'scaffold'}, database: true),
    ]);

    expect(code, 0, reason: errors.join('\n'));
    // No flutter create; the hand-written file is kept.
    expect(calls.where((c) => c.contains('create')), isEmpty);
    expect(File(appFile('web/index.html')).readAsStringSync(), 'mine');
    // The patch set ran: entitlements, wasm, worker.
    expect(
      File(appFile(kMacosEntitlements.first)).readAsStringSync(),
      contains('com.apple.security.network.client'),
    );
    expect(File(appFile('web/sqlite3.wasm')).existsSync(), isTrue);
    expect(File(appFile('web/drift_worker.js')).existsSync(), isTrue);
  });

  group('a second run', () {
    final mtime = DateTime(2001);

    /// Back-dates every file under the app, so a rewrite shows as a newer
    /// modification time even within the same second.
    void backdate() {
      for (final f in Directory(
        appFile(''),
      ).listSync(recursive: true).whereType<File>()) {
        f.setLastModifiedSync(mtime);
      }
    }

    List<String> rewritten() => [
      for (final f in Directory(
        appFile(''),
      ).listSync(recursive: true).whereType<File>())
        if (f.lastModifiedSync() != mtime)
          p.relative(f.path, from: appFile('')),
    ];

    final full = {'web': 'scaffold', 'macos': 'scaffold'};

    test('with nothing changed writes nothing — drift_worker.js included — '
        'and says the runner is up to date', () async {
      expect(
        await generate([app(platforms: full, database: true)]),
        0,
        reason: errors.join('\n'),
      );
      backdate();
      calls.clear();
      info.clear();

      expect(await generate([app(platforms: full, database: true)]), 0);

      expect(rewritten(), isEmpty);
      // The worker was compiled again, then left alone: same bytes.
      expect(calls.where((c) => c.contains('compile')), hasLength(1));
      expect(calls.where((c) => c.contains('create')), isEmpty);
      expect(pubGets, hasLength(1), reason: 'only the first run pub gets');
      expect(info.where((l) => l.contains('wrote')), isEmpty);
      expect(
        info,
        contains(
          '  apps/demo: up to date (web, macos) — nothing '
          'written',
        ),
      );
    });

    test(
      'rewrites drift_worker.js when its bytes changed, and only it',
      () async {
        expect(await generate([app(platforms: full, database: true)]), 0);
        backdate();
        info.clear();
        // As long as the old output, so only a byte-by-byte comparison sees
        // the change.
        workerOutput = '// WORKER';
        expect(workerOutput.length, '// worker'.length);

        expect(await generate([app(platforms: full, database: true)]), 0);

        expect(rewritten(), [p.join('web', 'drift_worker.js')]);
        expect(
          File(appFile('web/drift_worker.js')).readAsStringSync(),
          workerOutput,
        );
        expect(info, contains('    wrote apps/demo/web/drift_worker.js'));
        expect(info.where((l) => l.contains('up to date')), isEmpty);
      },
    );

    test(
      'a worker an older run compiled into web/ loses its .deps and .map',
      () async {
        expect(await generate([app(database: true)]), 0);
        _write(root, 'apps/demo/web/drift_worker.js.deps', 'deps');
        _write(root, 'apps/demo/web/drift_worker.js.map', 'map');
        info.clear();

        expect(await generate([app(database: true)]), 0);

        expect(File(appFile('web/drift_worker.js.deps')).existsSync(), isFalse);
        expect(File(appFile('web/drift_worker.js.map')).existsSync(), isFalse);
        expect(info.where((l) => l.contains('up to date')), isEmpty);
      },
    );

    group('a sqlite3.wasm in web/ that the resolved sqlite3 does not name', () {
      /// What an older sqlite3 release left in web/: as long as the current
      /// one, different bytes.
      final stale = List<int>.generate(64, (i) => 255 - i);

      /// The web runner as a run before a sqlite3 upgrade left it: the old
      /// wasm, and the worker this run compiles again (so only the wasm
      /// step can write).
      void staleRunner() {
        expect(sha256.convert(stale).toString(), isNot(wasmSha));
        File(appFile('web/sqlite3.wasm'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(stale);
        _write(root, 'apps/demo/web/drift_worker.js', workerOutput);
      }

      File cached() => File(
        p.join(cache.path, 'flutter_monorepo', 'sqlite3', tag, 'sqlite3.wasm'),
      );

      test('with no cached copy, is downloaded afresh and replaced', () async {
        staleRunner();

        expect(
          await generate([app(database: true)]),
          0,
          reason: errors.join('\n'),
        );

        expect(fetched, hasLength(1));
        expect(File(appFile('web/sqlite3.wasm')).readAsBytesSync(), wasm);
        expect(info, contains('    wrote apps/demo/web/sqlite3.wasm ($tag)'));
        expect(info.where((l) => l.contains('up to date')), isEmpty);
      });

      test('with a valid cached copy, is replaced from the cache', () async {
        staleRunner();
        cached()
          ..createSync(recursive: true)
          ..writeAsBytesSync(wasm);

        expect(
          await generate([app(database: true)]),
          0,
          reason: errors.join('\n'),
        );

        expect(fetched, isEmpty);
        expect(File(appFile('web/sqlite3.wasm')).readAsBytesSync(), wasm);
        expect(info, contains('    wrote apps/demo/web/sqlite3.wasm ($tag)'));
        expect(info.where((l) => l.contains('up to date')), isEmpty);
      });
    });

    test('a missing download is not called up to date', () async {
      Future<List<int>> offline(Uri url) async =>
          throw const SocketException('no route');
      expect(await generate([app(database: true)], fetch: offline), 0);
      info.clear();

      expect(await generate([app(database: true)], fetch: offline), 0);

      expect(warnings.last, contains('web database assets missing'));
      expect(info.where((l) => l.contains('up to date')), isEmpty);
    });
  });

  group('flutter pub get for a runner without its plugin files', () {
    test('runs in the app, after the create and before the patch set — '
        'once', () async {
      expect(
        await generate([
          app(platforms: {'linux': 'scaffold'}),
        ]),
        0,
        reason: errors.join('\n'),
      );

      final steps = [
        for (final c in calls) c.skip(1 + flutterArgs.length).take(2).join(' '),
      ];
      expect(steps.first, startsWith('create '));
      expect(steps.last, 'pub get');
      expect(pubGets, [p.join(root.path, 'apps', 'demo')]);
      expect(
        info,
        contains('    wrote apps/demo/${kPubGetRunnerFiles['linux']}'),
      );

      // A healthy runner: no create, and no pub get either.
      calls.clear();
      info.clear();
      expect(
        await generate([
          app(platforms: {'linux': 'scaffold'}),
        ]),
        0,
      );
      expect(calls, isEmpty);
      expect(pubGets, hasLength(1));
      expect(info, ['  apps/demo: up to date (linux) — nothing written']);
    });

    test('--offline runs `flutter pub get --offline`, which writes the '
        'plugin files from the pub cache', () async {
      final code = await generate(
        [
          app(platforms: {'linux': 'scaffold', 'macos': 'scaffold'}),
        ],
        request: const RunnersRequest(offline: true),
      );

      expect(code, 0, reason: errors.join('\n'));
      expect(pubGetArgs, [
        ['pub', 'get', '--offline'],
      ]);
      expect(File(appFile(kPubGetRunnerFiles['linux']!)).existsSync(), isTrue);
      expect(File(appFile(kPubGetRunnerFiles['macos']!)).existsSync(), isTrue);
      expect(warnings, isEmpty);
    });

    test('a failing pub get is repaired by the next run, never called up to '
        'date', () async {
      final linux = app(platforms: {'linux': 'scaffold'});
      expect(await generate([linux], run: fakeRun(pubGetExit: 69)), 1);
      expect(File(appFile('linux/runner.txt')).existsSync(), isTrue);
      expect(File(appFile(kPubGetRunnerFiles['linux']!)).existsSync(), isFalse);

      // Still failing: the folder exists, but pub get is tried again.
      info.clear();
      errors.clear();
      expect(await generate([linux], run: fakeRun(pubGetExit: 69)), 1);
      expect(pubGets, hasLength(2));
      expect(calls.where((c) => c.contains('create')), hasLength(1));
      expect(errors.join('\n'), contains('`flutter pub get` failed (exit 69)'));
      expect(info.where((l) => l.contains('up to date')), isEmpty);

      // It passes: the runner gets its plugin files, and says what it wrote.
      info.clear();
      errors.clear();
      expect(await generate([linux]), 0, reason: errors.join('\n'));
      expect(pubGets, hasLength(3));
      expect(File(appFile(kPubGetRunnerFiles['linux']!)).existsSync(), isTrue);
      expect(info.where((l) => l.contains('up to date')), isEmpty);

      // Now it is healthy, and only now up to date.
      info.clear();
      expect(await generate([linux]), 0);
      expect(pubGets, hasLength(3));
      expect(info, ['  apps/demo: up to date (linux) — nothing written']);
    });

    test('an --offline run whose pub cache lacks a package is repaired by the '
        'next online run', () async {
      final linux = app(platforms: {'linux': 'scaffold'});
      expect(
        await generate(
          [linux],
          request: const RunnersRequest(offline: true),
          run: fakeRun(pubGetExit: 69),
        ),
        1,
      );
      expect(
        errors.join('\n'),
        allOf(
          contains('`flutter pub get --offline` failed (exit 69)'),
          contains(
            'run `dart tools/composer/composer.dart runners --app demo` again '
            'online',
          ),
        ),
      );
      expect(File(appFile(kPubGetRunnerFiles['linux']!)).existsSync(), isFalse);

      info.clear();
      errors.clear();
      expect(await generate([linux]), 0, reason: errors.join('\n'));
      expect(pubGetArgs.last, ['pub', 'get']);
      expect(File(appFile(kPubGetRunnerFiles['linux']!)).existsSync(), isTrue);
      expect(info.where((l) => l.contains('up to date')), isEmpty);
    });

    test('a runner an older composer left without its plugin files gets '
        'pub get, and no create', () async {
      // Each runner folder as `flutter create --no-pub` alone leaves it.
      for (final platform in ['linux', 'windows', 'macos']) {
        _write(root, 'apps/demo/$platform/runner.txt', platform);
      }
      for (final file in kMacosEntitlements) {
        _write(root, 'apps/demo/$file', macosEntitlements);
      }

      final code = await generate([
        app(
          platforms: {
            'linux': 'scaffold',
            'windows': 'scaffold',
            'macos': 'scaffold',
          },
        ),
      ]);

      expect(code, 0, reason: errors.join('\n'));
      expect(calls.where((c) => c.contains('create')), isEmpty);
      expect(pubGets, [p.join(root.path, 'apps', 'demo')]);
      for (final platform in ['linux', 'windows', 'macos']) {
        final file = kPubGetRunnerFiles[platform]!;
        expect(File(appFile(file)).existsSync(), isTrue, reason: file);
        expect(info, contains('    wrote apps/demo/$file'));
      }
    });

    test('a pub get that passes but writes no plugin file is an error naming '
        'it', () async {
      final code = await generate([
        app(platforms: {'linux': 'scaffold'}),
      ], run: fakeRun(pubGetWrites: false));

      expect(code, 1);
      expect(
        errors.join('\n'),
        contains(
          'apps/demo: `flutter pub get` passed but wrote no '
          '${kPubGetRunnerFiles['linux']}',
        ),
      );
      expect(info.where((l) => l.contains('up to date')), isEmpty);
    });

    test('a web runner has no plugin file to check: a healthy one gets no '
        'pub get', () async {
      expect(await generate([app()]), 0, reason: errors.join('\n'));
      expect(pubGets, hasLength(1), reason: 'the new runner');
      info.clear();

      expect(await generate([app()]), 0);
      expect(pubGets, hasLength(1));
      expect(info, ['  apps/demo: up to date (web) — nothing written']);
    });

    test('--offline downloads nothing; a cached wasm is still used', () async {
      expect(
        await generate(
          [app(database: true)],
          request: const RunnersRequest(offline: true),
        ),
        0,
      );
      expect(fetched, isEmpty);
      expect(warnings.join('\n'), contains('--offline, and no cached copy'));
      expect(File(appFile('web/sqlite3.wasm')).existsSync(), isFalse);

      // Cached by an online run (of another app, say): offline uses it.
      File(appFile('web/sqlite3.wasm')).parent.createSync(recursive: true);
      File(
          p.join(
            cache.path,
            'flutter_monorepo',
            'sqlite3',
            tag,
            'sqlite3.wasm',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsBytesSync(wasm);
      expect(
        await generate(
          [app(database: true)],
          request: const RunnersRequest(offline: true),
        ),
        0,
      );
      expect(fetched, isEmpty);
      expect(File(appFile('web/sqlite3.wasm')).readAsBytesSync(), wasm);
    });

    test(
      'a failing pub get is named, and exit is 1; the runner stays',
      () async {
        final code = await generate(
          [
            app(platforms: {'linux': 'scaffold'}),
          ],
          run: fakeRun(pubGetExit: 69),
        );

        expect(code, 1);
        expect(
          errors.join('\n'),
          contains('apps/demo: `flutter pub get` failed (exit 69)'),
        );
        expect(File(appFile('linux/runner.txt')).existsSync(), isTrue);
      },
    );
  });

  test('a failing flutter create is named, and exit is 1', () async {
    final code = await generate([app()], run: fakeRun(createExit: 3));

    expect(code, 1);
    expect(errors.join('\n'), contains('failed (exit 3)'));
    expect(Directory(appFile('web')).existsSync(), isFalse);
  });

  group('the arguments', () {
    test('--app, --platform (repeatable, comma-separated), --force and '
        '--offline', () {
      final request = parseRunnersArgs([
        '--app',
        'admin',
        '--platform',
        'web,linux',
        '--platform',
        'macos',
        '--force',
        '--offline',
      ]);
      expect(request.app, 'admin');
      expect(request.platforms, ['web', 'linux', 'macos']);
      expect(request.force, isTrue);
      expect(request.offline, isTrue);
      expect(parseRunnersArgs(const []).offline, isFalse);
    });

    test('an unknown platform, flag or missing value is a usage error', () {
      for (final args in [
        ['--platform', 'tizen'],
        ['--stray'],
        ['--app'],
        ['--platform', '--force'],
      ]) {
        expect(
          () => parseRunnersArgs(args),
          throwsFormatException,
          reason: '$args',
        );
      }
    });

    test('an unknown app is an error naming the known ones', () async {
      final code = await generate([
        app(),
      ], request: const RunnersRequest(app: 'nope'));
      expect(code, 1);
      expect(errors.join('\n'), contains('Known: demo'));
    });
  });
}

void _write(Directory root, String rel, String content) {
  File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}
