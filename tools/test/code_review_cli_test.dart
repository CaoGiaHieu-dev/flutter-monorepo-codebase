import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/tool_harness.dart';

/// `tools/code_review/code_review.dart` — the command line, as a process.
///
/// Covers everything decided before a request would be sent: the argument
/// parser, `--help`, `--show-config`, `--config` (answers piped to stdin),
/// the not-found and not-a-project exits, where the API key comes from (shown
/// masked on the first output line, so no request is needed to see it), and
/// the "nothing to review" exit. Every run uses a snapshot copied into a temp
/// directory, so `code_review_config.json`, `.gemini_api_key` and
/// `review_prompt.md` are the ones the test writes there — never the tracked
/// config. No case reaches Gemini: the review itself is covered through
/// `ApiService`'s injectable client in `code_review_test.dart`.
void main() {
  late CompiledTool tool;
  setUpAll(() async {
    tool = await CompiledTool.compile('tools/code_review/code_review.dart');
  });
  tearDownAll(() => tool.dispose());

  /// Where the tool's own files go: its snapshot sits in
  /// `<workspace>/tools/code_review/`.
  const toolDir = 'tools/code_review';

  /// A Flutter-looking workspace with one reviewable file.
  TempWorkspace workspace([Map<String, String> more = const {}]) =>
      TempWorkspace.create({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/mobile\n',
        'apps/mobile/lib/main.dart': 'void main() {}\n',
        'apps/mobile/lib/main.g.dart': '// generated\n',
        ...more,
      });

  /// No key in the environment, whatever the developer's shell holds.
  const noKey = {'GEMINI_API_KEY': ''};

  Future<ToolRun> run(
    TempWorkspace ws,
    List<String> args, {
    Map<String, String> environment = noKey,
    String? stdin,
  }) => tool.run(
    args,
    workingDirectory: ws.root,
    scriptPath: '$toolDir/code_review.dill',
    environment: environment,
    stdin: stdin,
  );

  group('arguments', () {
    test('--help prints the usage and exits 0', () async {
      final run0 = await run(workspace(), ['--help']);

      expect(run0, exitsWith(0));
      expect(
        run0.stdout,
        contains('Usage: dart tools/code_review/code_review.dart [options]'),
      );
      expect(run0.stdout, contains('--all'));
      expect(run0.stdout, contains('--folder'));
      expect(run0.stdout, contains('--exclude'));
      expect(run0.stdout, contains('--language'));
      expect(run0.stdout, contains('API Key Setup'));
      expect(run0.stdout, contains('GEMINI_API_KEY'));
    });

    test('-h is the same as --help', () async {
      final run0 = await run(workspace(), ['-h']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Usage:'));
    });

    test('an unknown flag exits 64 with the usage', () async {
      final run0 = await run(workspace(), ['--frobnicate']);

      expect(run0, exitsWith(64));
      expect(
        run0.stderr,
        contains('Could not find an option named "--frobnicate"'),
      );
      expect(run0.stderr, contains('--help'));
    });

    test('a stray positional argument exits 64', () async {
      final run0 = await run(workspace(), ['--all', 'lib/main.dart']);

      expect(run0, exitsWith(64));
      expect(run0.stderr, contains('Unexpected argument(s): lib/main.dart'));
    });

    test('an option missing its value exits 64', () async {
      final run0 = await run(workspace(), ['--folder']);

      expect(run0, exitsWith(64));
      expect(run0.stderr, contains('Missing argument for "--folder"'));
    });

    for (final bad in const [
      ['--language', 'xx'],
      ['--focus', 'colour'],
      ['--format', 'html'],
    ]) {
      test('${bad.join(' ')} is not an allowed value: exit 64', () async {
        final run0 = await run(workspace(), [...bad, '--all']);

        expect(run0, exitsWith(64));
        expect(run0.stderr, contains('is not an allowed value'));
      });
    }

    test(
      'a bad option value is an error even next to --help',
      () async {
        // The parser runs first: a bad value is an error even next to --help.
        final run0 = await run(workspace(), ['--help', '--language', 'xx']);

        expect(run0, exitsWith(64));
      },
    );
  });

  group('--show-config', () {
    test('without a config file prints the defaults', () async {
      final run0 = await run(workspace(), ['--show-config']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Report Language: English (en)'));
      expect(run0.stdout, contains('Batch Size: 5'));
      expect(run0.stdout, contains('Delay Between Batches: 2000ms'));
      expect(run0.stdout, contains('Include Timestamps: true'));
      expect(run0.stdout, contains('markdown'));
      expect(run0.stdout, isNot(contains('API Key')));
    });

    test('reads the config next to the script', () async {
      final ws = workspace({
        '$toolDir/code_review_config.json': '{"reportLanguage": "ja", "batchSize": 9, "includeTimestamps": false}',
      });

      final run0 = await run(ws, ['--show-config']);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Report Language: 日本語 (ja)'));
      expect(run0.stdout, contains('Batch Size: 9'));
      expect(run0.stdout, contains('Include Timestamps: false'));
    });

    test('shows a key stored in the config masked, never whole', () async {
      final ws = workspace({
        '$toolDir/code_review_config.json':
            '{"geminiApiKey": "AIzaSyD-very-secret-0123456789"}',
      });

      final run0 = await run(ws, ['--show-config']);

      expect(run0.stdout, contains('API Key: AIza…'));
      expect(run0.stdout, isNot(contains('very-secret')));
    });
  });

  group('--config', () {
    test('saves the answers to the config next to the script', () async {
      final ws = workspace();

      // language 3 (ja), batch 8, delay 1500, timestamps no, detailed yes.
      final run0 = await run(ws, ['--config'], stdin: '3\n8\n1500\nn\ny\n');

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('Configuration saved successfully'));
      final saved = jsonDecode(
        ws.read('$toolDir/code_review_config.json'),
      ) as Map<String, dynamic>;
      expect(saved['reportLanguage'], 'ja');
      expect(saved['batchSize'], 8);
      expect(saved['delayBetweenBatches'], 1500);
      expect(saved['includeTimestamps'], isFalse);
      expect(saved['detailedOutput'], isTrue);
    });

    test(
      'out-of-range or unreadable numbers keep the current values',
      () async {
        final ws = workspace();

        final run0 = await run(ws, ['--config'], stdin: '1\n99\nsoon\n\n\n');

        expect(run0, exitsWith(0));
        final saved = jsonDecode(
          ws.read('$toolDir/code_review_config.json'),
        ) as Map<String, dynamic>;
        expect(saved['reportLanguage'], 'en');
        expect(saved['batchSize'], 5);
        expect(saved['delayBetweenBatches'], 2000);
        // Empty answers mean yes.
        expect(saved['includeTimestamps'], isTrue);
        expect(saved['detailedOutput'], isTrue);
      },
    );

    test('keeps the keys it does not ask about', () async {
      final ws = workspace({
        '$toolDir/code_review_config.json':
            '{"geminiApiKey": "kept", "custom": 1}',
      });

      await run(ws, ['--config'], stdin: '2\n\n\n\n\n');

      final saved = jsonDecode(
        ws.read('$toolDir/code_review_config.json'),
      ) as Map<String, dynamic>;
      expect(saved['geminiApiKey'], 'kept');
      expect(saved['custom'], 1);
      expect(saved['reportLanguage'], 'vi');
    });
  });

  group('before any request', () {
    test(
      'a --file that does not exist exits 1 before the key is looked up',
      () async {
        final run0 = await run(workspace(), ['--file', 'lib/ghost.dart']);

        expect(run0, exitsWith(1));
        expect(run0.stderr, contains('Not found: lib/ghost.dart'));
        expect(run0.output, isNot(contains('API key not found')));
      },
    );

    test('every missing --file is listed', () async {
      final run0 = await run(workspace(), [
        '--file',
        'a.dart',
        '--file',
        'b.dart',
      ]);

      expect(run0, exitsWith(1));
      expect(run0.stderr, contains('Not found: a.dart'));
      expect(run0.stderr, contains('Not found: b.dart'));
    });

    test('a --folder that does not exist exits 1', () async {
      final run0 = await run(workspace(), ['--folder', 'nowhere']);

      expect(run0, exitsWith(1));
      expect(run0.stderr, contains('Not found: nowhere'));
    });

    test(
      'no key anywhere and no terminal exits 1 and says where to put one',
      () async {
        final run0 = await run(workspace(), [
          '--file',
          'apps/mobile/lib/main.dart',
        ]);

        expect(run0, exitsWith(1));
        expect(run0.output, contains('Gemini API key not found'));
        expect(run0.output, contains('GEMINI_API_KEY'));
        expect(run0.output, contains('--api-key'));
        expect(run0.output, contains('No API key and no terminal'));
      },
    );

    test('outside a Flutter project it exits 1', () async {
      final ws = TempWorkspace.create({'notes.dart': 'void main() {}\n'});

      final run0 = await run(ws, ['--file', 'notes.dart', '--api-key', 'k']);

      expect(run0, exitsWith(1));
      expect(run0.output, contains("doesn't appear to be a Flutter project"));
    });

    test(
      'files that are all generated or tests leave nothing to review: exit 0',
      () async {
        final run0 = await run(workspace(), [
          '--file',
          'apps/mobile/lib/main.g.dart',
          '--api-key',
          'AIzaSyD-not-a-real-key-0123456789abcd',
        ]);

        expect(run0, exitsWith(0));
        expect(run0.stdout, contains('No files found to review.'));
      },
    );

    test(
      'a folder with nothing reviewable leaves nothing to review: exit 0',
      () async {
        final ws = workspace({
          'apps/mobile/lib/empty/only.g.dart': '// generated\n',
        });

        final run0 = await run(ws, [
          '--folder',
          'apps/mobile/lib/empty',
          '--api-key',
          'AIzaSyD-not-a-real-key-0123456789abcd',
        ]);

        expect(run0, exitsWith(0));
        expect(run0.stdout, contains('No files found to review.'));
      },
    );

    test('--exclude takes a file out of the review', () async {
      final run0 = await run(workspace(), [
        '--file',
        'apps/mobile/lib/main.dart',
        '--exclude',
        '**/main.dart',
        '--api-key',
        'AIzaSyD-not-a-real-key-0123456789abcd',
      ]);

      expect(run0, exitsWith(0));
      expect(run0.stdout, contains('No files found to review.'));
    });
  });

  group('the API key source', () {
    // The tool prints the key it chose, masked, before it looks at the
    // project — so the source is visible without sending a request. These
    // runs use a directory that is not a Flutter project and stop there.
    Future<ToolRun> keyed(
      TempWorkspace ws, {
      List<String> args = const [],
      Map<String, String> environment = noKey,
    }) => run(
      ws,
      ['--file', 'notes.dart', ...args],
      environment: environment,
    );

    TempWorkspace bare([Map<String, String> more = const {}]) =>
        TempWorkspace.create({'notes.dart': 'void main() {}\n', ...more});

    test('--api-key is used and printed masked', () async {
      final run0 = await keyed(
        bare(),
        args: ['--api-key', 'AIzaFromTheArgument-0123456789'],
      );

      expect(run0.stdout, contains('API Key: AIza…'));
      expect(run0.output, isNot(contains('FromTheArgument')));
    });

    test('a short key is masked to its length', () async {
      final run0 = await keyed(bare(), args: ['--api-key', 'abc']);

      expect(run0.stdout, contains('API Key: *** (3 chars)'));
    });

    test('GEMINI_API_KEY is used when there is no --api-key', () async {
      final run0 = await keyed(
        bare(),
        environment: {'GEMINI_API_KEY': 'ENVKEY-0123456789-abcdef'},
      );

      expect(run0.stdout, contains('API Key: ENVK…'));
    });

    test('--api-key wins over GEMINI_API_KEY', () async {
      final run0 = await keyed(
        bare(),
        args: ['--api-key', 'ARGKEY-0123456789-abcdef'],
        environment: {'GEMINI_API_KEY': 'ENVKEY-0123456789-abcdef'},
      );

      expect(run0.stdout, contains('API Key: ARGK…'));
    });

    test('the saved .gemini_api_key is next, then the config file', () async {
      final both = bare({
        '$toolDir/.gemini_api_key': 'SAVED-0123456789-abcdef\n',
        '$toolDir/code_review_config.json':
            '{"geminiApiKey": "CONFIG-0123456789-abcdef"}',
      });
      final onlyConfig = bare({
        '$toolDir/code_review_config.json':
            '{"geminiApiKey": "CONFIG-0123456789-abcdef"}',
      });

      expect((await keyed(both)).stdout, contains('API Key: SAVE…'));
      expect((await keyed(onlyConfig)).stdout, contains('API Key: CONF…'));
    });

    test('the environment wins over the saved key', () async {
      final ws = bare({
        '$toolDir/.gemini_api_key': 'SAVED-0123456789-abcdef\n',
      });

      final run0 = await keyed(
        ws,
        environment: {'GEMINI_API_KEY': 'ENVKEY-0123456789-abcdef'},
      );

      expect(run0.stdout, contains('API Key: ENVK…'));
    });
  });

  test(
    'the tracked config file is valid JSON with the keys the tool reads',
    () {
      final tracked = File(
        p.join(repoRoot, 'tools', 'code_review', 'code_review_config.json'),
      );

      final config =
          jsonDecode(tracked.readAsStringSync()) as Map<String, dynamic>;

      expect(config['reportLanguage'], isA<String>());
      expect(config['batchSize'], isA<int>());
      expect(config['delayBetweenBatches'], isA<int>());
      expect(
        config.containsKey('geminiApiKey'),
        isFalse,
        reason: 'a key never belongs in the tracked config',
      );
    },
  );
}
