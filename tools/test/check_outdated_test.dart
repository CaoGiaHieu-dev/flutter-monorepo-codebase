import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../check_outdated.dart';
import 'support/fake_bin.dart';
import 'support/tool_harness.dart';

/// `tools/check_outdated.dart` — the outdated-dependency report.
///
/// The decisions are pure functions ([findOutdated], [applyUpdates],
/// [toggleSelection], [sandboxPubspec]) tested directly. The tool as a whole
/// runs as a process against a temp workspace with a fake `dart` on `PATH`
/// standing in for `pub get` / `pub outdated`, so nothing reaches pub.dev.
void main() {
  const catalog = '''
# Source of truth.
dependencies:
  # Networking
  dio: "^5.11.0"
  provider: "^6.1.5+1"
  flutter_secure_storage: "11.2.0"
  unquoted: ^1.0.0
  commented: ^1.6.0  # pinned on purpose
  up_to_date: "^3.0.0"
''';

  Map<String, dynamic> pub(String name, String latest) => {
    'package': name,
    'latest': {'version': latest},
  };

  group('findOutdated', () {
    test('lists a package whose pin differs from the latest version', () {
      final found = findOutdated(catalog, [pub('dio', '5.12.0')]);

      expect(found, hasLength(1));
      expect(found.single.name, 'dio');
      expect(found.single.current, '5.11.0');
      expect(found.single.latest, '5.12.0');
      expect(found.single.selected, isTrue);
    });

    test('a package already at its latest version is not listed', () {
      expect(findOutdated(catalog, [pub('up_to_date', '3.0.0')]), isEmpty);
    });

    test('a package the catalog does not pin is not listed', () {
      expect(findOutdated(catalog, [pub('not_in_catalog', '9.0.0')]), isEmpty);
    });

    test('an entry without a latest version is skipped', () {
      expect(
        findOutdated(catalog, [
          {'package': 'dio', 'latest': null},
          {'package': 'dio'},
          {
            'latest': {'version': '1.0.0'},
          },
        ]),
        isEmpty,
      );
    });

    test('reads a "+build" version, an exact pin and an unquoted pin', () {
      final found = findOutdated(catalog, [
        pub('provider', '6.2.0'),
        pub('flutter_secure_storage', '11.3.0'),
        pub('unquoted', '2.0.0'),
      ]);

      expect(
        {for (final f in found) f.name: f.current},
        {
          'provider': '6.1.5+1',
          'flutter_secure_storage': '11.2.0',
          'unquoted': '1.0.0',
        },
      );
    });

    test('a trailing comment is not part of the version', () {
      // The version used to be read to the end of the line, so this entry
      // looked outdated against itself and applying it ate the comment.
      expect(findOutdated(catalog, [pub('commented', '1.6.0')]), isEmpty);
    });

    test('a package name is matched whole, never as a suffix', () {
      final found = findOutdated('dependencies:\n  my_dio: "^1.0.0"\n', [
        pub('dio', '9.0.0'),
      ]);

      expect(found, isEmpty);
    });
  });

  group('applyUpdates', () {
    test('bumps only the selected packages and keeps the `^` and quotes', () {
      final found = findOutdated(catalog, [
        pub('dio', '5.12.0'),
        pub('provider', '6.2.0'),
      ]);
      found.last.selected = false;

      final updated = applyUpdates(catalog, found.where((f) => f.selected));

      expect(updated, contains('dio: "^5.12.0"'));
      expect(updated, contains('provider: "^6.1.5+1"'));
    });

    test('keeps the comments and every other line untouched', () {
      final found = findOutdated(catalog, [
        pub('commented', '1.7.0'),
        pub('flutter_secure_storage', '12.0.0'),
      ]);

      final updated = applyUpdates(catalog, found);

      expect(updated, contains('commented: ^1.7.0  # pinned on purpose'));
      expect(updated, contains('flutter_secure_storage: "12.0.0"'));
      expect(updated, contains('# Networking'));
      expect(updated, contains('up_to_date: "^3.0.0"'));
    });

    test('nothing selected leaves the catalog byte for byte', () {
      expect(applyUpdates(catalog, const []), catalog);
    });
  });

  group('toggleSelection', () {
    List<OutdatedPackage> three() => findOutdated(
      'dependencies:\n  a: "^1.0.0"\n  b: "^1.0.0"\n  c: "^1.0.0"\n',
      [pub('a', '2.0.0'), pub('b', '2.0.0'), pub('c', '2.0.0')],
    );

    test('flips the numbered entries', () {
      final list = three();

      toggleSelection(list, '1,3');

      expect(list.map((e) => e.selected), [false, true, false]);
    });

    test('a second toggle flips it back', () {
      final list = three();

      toggleSelection(list, '2');
      toggleSelection(list, '2');

      expect(list.every((e) => e.selected), isTrue);
    });

    test('ignores zero, out-of-range numbers and words', () {
      final list = three();

      toggleSelection(list, '0, 4, x, -1');

      expect(list.every((e) => e.selected), isTrue);
    });
  });

  test('sandboxPubspec wraps the catalog in a valid package header', () {
    final pubspec = sandboxPubspec(catalog);

    expect(pubspec, startsWith('name: outdated_check\n'));
    expect(pubspec, contains("publish_to: 'none'"));
    expect(pubspec, contains('environment:'));
    expect(pubspec, contains('dio: "^5.11.0"'));
  });

  group('as a process', () {
    late CompiledTool tool;
    setUpAll(() async {
      tool = await CompiledTool.compile('tools/check_outdated.dart');
    });
    tearDownAll(() => tool.dispose());

    TempWorkspace workspace({String? catalogText = catalog}) =>
        TempWorkspace.create({
          'pubspec_dependencies.yaml': ?catalogText,
        });

    /// A fake `dart` that answers `pub get`, `pub outdated` and
    /// `pub outdated --json`.
    FakeBin fakeDart({
      int getExit = 0,
      int outdatedExit = 0,
      int jsonExit = 0,
      String json = '{"packages": []}',
    }) => FakeBin.create({
      'dart':
          '''
case "\$*" in
  "pub get")
    [ $getExit -ne 0 ] && echo "version solving failed" >&2
    exit $getExit ;;
  "pub outdated --json")
    cat <<'JSON'
$json
JSON
    exit $jsonExit ;;
  "pub outdated")
    echo "Showing outdated packages."
    exit $outdatedExit ;;
esac
exit 3
''',
    });

    Future<ToolRun> run(
      TempWorkspace ws, {
      List<String> args = const [],
      FakeBin? bin,
    }) => tool.run(
      args,
      workingDirectory: ws.root,
      environment: bin?.environment,
    );

    test('--help prints the usage and exits 0', () async {
      final run0 = await run(workspace(), args: ['--help']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage: dart tools/check_outdated.dart'));
      expect(run0.stdout, contains('pubspec_dependencies.yaml'));
    });

    test('-h is the same as --help', () async {
      final run0 = await run(workspace(), args: ['-h']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage:'));
    });

    test('an unknown argument exits 64 with the usage', () async {
      final run0 = await run(workspace(), args: ['--apply']);

      expect(run0, exitsWith(64));
      expect(run0.output, contains('Unknown argument(s): --apply'));
      expect(run0.stderr, contains('Usage:'));
    });

    test('a workspace without the catalog exits 1', () async {
      final ws = workspace(catalogText: null);

      final run0 = await run(ws);

      expect(run0, exitsWith(1));
      expect(run0.output, contains('pubspec_dependencies.yaml not found'));
    });

    test(
      'a sandbox that does not resolve exits 1 and is removed',
      () async {
        final ws = workspace();

        final run0 = await run(ws, bin: fakeDart(getExit: 1));

        expect(run0, exitsWith(1));
        expect(run0.output, contains('Failed to resolve dependencies'));
        expect(run0.output, contains('version solving failed'));
        expect(ws.exists('.dart_tool/outdated_check'), isFalse);
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'a failing `pub outdated` exits 1',
      () async {
        final run0 = await run(
          workspace(),
          bin: fakeDart(outdatedExit: 2),
        );

        expect(run0, exitsWith(1));
        expect(run0.output, contains('Outdated check finished with code: 2'));
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'outdated packages are reported, and without a terminal the catalog is '
      'left alone',
      () async {
        final ws = workspace();
        final bin = fakeDart(
          json:
              '{"packages": ['
              '{"package": "dio", "latest": {"version": "5.12.0"}},'
              '{"package": "up_to_date", "latest": {"version": "3.0.0"}},'
              '{"package": "other", "latest": {"version": "1.0.0"}}'
              ']}',
        );

        final run0 = await run(ws, bin: bin);

        expect(run0, exitsWith(0));
        expect(run0.stdout, contains('report only, no terminal'));
        expect(run0.stdout, contains('- dio (5.11.0 -> 5.12.0)'));
        expect(run0.stdout, isNot(contains('up_to_date')));
        expect(ws.read('pubspec_dependencies.yaml'), catalog);
        expect(ws.exists('.dart_tool/outdated_check'), isFalse);
        // The sandbox got the catalog's own dependencies.
        expect(
          bin.calls.where(
            (c) => c.contains(p.join('.dart_tool', 'outdated_check')),
          ),
          isNotEmpty,
        );
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'a catalog already at the latest versions says so and exits 0',
      () async {
        final run0 = await run(
          workspace(),
          bin: fakeDart(
            json: '{"packages": [{"package": "dio", "latest": {"version": "5.11.0"}}]}',
          ),
        );

        expect(run0, exitsWith(0));
        expect(run0.stdout, contains('already at their latest versions'));
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'unreadable `pub outdated --json` output exits 1',
      () async {
        final run0 = await run(workspace(), bin: fakeDart(json: 'not json'));

        expect(run0, exitsWith(1));
        expect(run0.output, contains('Failed to parse JSON from pub outdated'));
      },
      skip: skipWithoutPosixShell(),
    );

    test(
      'a failing `pub outdated --json` exits 1',
      () async {
        final run0 = await run(workspace(), bin: fakeDart(jsonExit: 1));

        expect(run0, exitsWith(1));
        expect(run0.output, contains('Error running pub outdated --json'));
      },
      skip: skipWithoutPosixShell(),
    );
  });
}
