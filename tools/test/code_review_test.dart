import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../code_review/code_review_api.dart';

/// `tools/code_review` — the Gemini review tool, below the command line.
///
/// Pure logic (file classification, pattern matching, prompt building,
/// parsing a review, rendering the report) is called directly. The Gemini
/// call is exercised through `ApiService`'s injectable `http.Client`
/// (`package:http/testing.dart`), so no key and no network are involved.
///
/// The tool keeps its config, saved key and prompt next to its script
/// (`CodeReviewConstants.toolDir`). Under `dart test` there is no such
/// script, so every test points `toolDirOverride` at a temp directory — the
/// tracked `code_review_config.json` is never read or written.
void main() {
  late Directory toolDir;

  setUp(() {
    toolDir = Directory.systemTemp.createTempSync('code_review_tool_');
    CodeReviewConstants.toolDirOverride = toolDir.path;
    ConfigService.languageOverride = null;
  });

  tearDown(() {
    CodeReviewConstants.toolDirOverride = null;
    ConfigService.languageOverride = null;
    if (toolDir.existsSync()) toolDir.deleteSync(recursive: true);
  });

  group('FileAnalyzer.getFileType', () {
    const cases = {
      'lib/pages/login_page.dart': FileType.page,
      'lib/widgets/card_widget.dart': FileType.widget,
      'lib/provider/login_provider.dart': FileType.provider,
      'lib/entities/user_entity.dart': FileType.entity,
      'lib/use_cases/get_user_usecase.dart': FileType.useCase,
      'lib/repositories/user_repository.dart': FileType.repository,
      'lib/repositories/user_repository_impl.dart': FileType.repositoryImpl,
      'lib/data_sources/user_data_source.dart': FileType.dataSource,
      'lib/utils/app_constants.dart': FileType.constants,
      'lib/utils/env_config.dart': FileType.config,
      'lib/models/user_model.dart': FileType.model,
      'lib/params/login_params.dart': FileType.parameters,
      'lib/main.dart': FileType.dartFile,
    };
    cases.forEach((path, type) {
      test('$path is a ${type.displayName}', () {
        expect(FileAnalyzer.getFileType(path), type);
      });
    });
  });

  group('FileAnalyzer.getArchitectureLayer', () {
    const cases = {
      'modules/auth/domain/lib/a.dart': ArchitectureLayer.domain,
      'modules/auth/data/lib/a.dart': ArchitectureLayer.data,
      'modules/auth/feature/lib/a.dart': ArchitectureLayer.presentation,
      'platform/foundation/core_di/lib/a.dart': ArchitectureLayer.core,
      'apps/mobile/lib/main.dart': ArchitectureLayer.presentation,
      'modules/auth/domain/lib/gen/a.dart': ArchitectureLayer.generated,
      'platform/x/lib/generated/a.dart': ArchitectureLayer.generated,
      'somewhere/else/a.dart': ArchitectureLayer.unknown,
      r'modules\auth\domain\lib\a.dart': ArchitectureLayer.domain,
      '/abs/checkout/modules/auth/data/lib/a.dart': ArchitectureLayer.data,
    };
    cases.forEach((path, layer) {
      test('$path is ${layer.displayName}', () {
        expect(FileAnalyzer.getArchitectureLayer(path), layer);
      });
    });

    test('a directory that merely contains "modules" is not a module', () {
      expect(
        FileAnalyzer.getArchitectureLayer('my_modules/auth/domain/a.dart'),
        ArchitectureLayer.unknown,
      );
    });
  });

  group('FileAnalyzer.matchesPattern', () {
    test('a single * stays inside one path segment', () {
      expect(FileAnalyzer.matchesPattern('lib/a.dart', 'lib/*.dart'), isTrue);
      expect(
        FileAnalyzer.matchesPattern('lib/sub/a.dart', 'lib/*.dart'),
        isFalse,
      );
    });

    test('**/ spans any number of directories', () {
      expect(
        FileAnalyzer.matchesPattern('a/b/c/routing/x.dart', '**/routing/**'),
        isTrue,
      );
      expect(
        FileAnalyzer.matchesPattern(
          'modules/a/b/routing/x.dart',
          'modules/**/routing/**',
        ),
        isTrue,
      );
    });

    test('a literal prefix still has to match', () {
      expect(
        FileAnalyzer.matchesPattern(
          'apps/a/b/routing/x.dart',
          'modules/**/routing/**',
        ),
        isFalse,
      );
    });

    test('? matches one character', () {
      expect(FileAnalyzer.matchesPattern('lib/a1.dart', 'lib/a?.dart'), isTrue);
      expect(
        FileAnalyzer.matchesPattern('lib/a12.dart', 'lib/a?.dart'),
        isFalse,
      );
    });

    test('a pattern with no wildcard is a substring test', () {
      expect(
        FileAnalyzer.matchesPattern('lib/legacy/old.dart', 'legacy'),
        isTrue,
      );
      expect(FileAnalyzer.matchesPattern('lib/new.dart', 'legacy'), isFalse);
    });
  });

  group('FileAnalyzer.isGeneratedOrTest', () {
    const excluded = [
      'lib/a.g.dart',
      'lib/a.freezed.dart',
      'lib/a.config.dart',
      'lib/a.module.dart',
      'lib/a.gen.dart',
      'lib/a.mocks.dart',
      'lib/firebase/firebase_options_dev.dart',
      'lib/src/gen/a.dart',
      'lib/generated/a.dart',
      'test/a_test.dart',
      'pkg/test/a_test.dart',
      '.dart_tool/a.dart',
      'build/a.dart',
      r'pkg\test\a_test.dart',
    ];
    for (final path in excluded) {
      test('$path is excluded', () {
        expect(FileAnalyzer.isGeneratedOrTest(path), isTrue);
      });
    }

    const kept = [
      'lib/a.dart',
      'lib/generator.dart',
      'lib/testing_utils.dart',
      'modules/auth/feature/lib/pages/login_page.dart',
    ];
    for (final path in kept) {
      test('$path is reviewed', () {
        expect(FileAnalyzer.isGeneratedOrTest(path), isFalse);
      });
    }
  });

  group('enums', () {
    test('every file type and layer has a display name', () {
      for (final type in FileType.values) {
        expect(type.displayName, isNotEmpty);
      }
      for (final layer in ArchitectureLayer.values) {
        expect(layer.displayName, isNotEmpty);
      }
    });
  });

  group('ReviewResult.fromAiResponse', () {
    const review = '''
## 📝 Code Review: `login_page.dart`

### 🚨 Issues Identified
#### Critical
1. **Hardcoded API key** on line 3
   - move it to the environment
2. **Missing dispose** of the controller
- not numbered, so not an issue title

### 🚀 Improvement Suggestions
1. **Use const constructors**
- Extract the header widget
* Prefer final

### ✅ Positive Aspects
- Clear naming

### 📈 Overall Rating
| Category | Score |
|---|---|
| **Architecture** | 8/10 |
| Naming | 9/10 |
''';

    test('reads the numbered issue titles, bold stripped', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'lib/login_page.dart',
        review: review,
      );

      expect(result.issues, [
        'Hardcoded API key on line 3',
        'Missing dispose of the controller',
      ]);
      expect(result.fileName, 'login_page.dart');
      expect(result.filePath, 'lib/login_page.dart');
    });

    test('reads suggestions, numbered or bulleted', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review: review,
      );

      expect(result.suggestions, [
        'Use const constructors',
        'Extract the header widget',
        'Prefer final',
      ]);
    });

    test('reads the ratings table and skips its header row', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review: review,
      );

      expect(result.ratings, {'Architecture': 8, 'Naming': 9});
    });

    test('a review with an issue marked critical has errors', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review: '### 🚨 Issues Identified\n1. 🔴 Critical: SQL injection\n',
      );

      expect(result.hasErrors, isTrue);
      expect(result.issues, ['🔴 Critical: SQL injection']);
    });

    test('a review with only ordinary issues has no errors', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review: review,
      );

      expect(result.hasErrors, isFalse);
    });

    test('"none found" lines and headings are not issues', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review:
            '### 🚨 Issues Identified\n#### Critical Violations\nNone found\n\n'
            '### ✅ Positive Aspects\n- fine\n',
      );

      expect(result.issues, isEmpty);
      expect(result.hasErrors, isFalse);
    });

    test('a review without sections has no issues, suggestions or ratings', () {
      final result = ReviewResult.fromAiResponse(
        filePath: 'a.dart',
        review: 'Looks fine to me.',
      );

      expect(result.issues, isEmpty);
      expect(result.suggestions, isEmpty);
      expect(result.ratings, isEmpty);
      expect(result.review, 'Looks fine to me.');
    });

    for (final technical in const [
      'Error: boom',
      'something ApiRateLimitException something',
      'ApiTimeoutException: Request timeout',
      'Max retries exceeded due to rate limiting',
    ]) {
      test('"$technical" is a technical failure, not a code issue', () {
        final result = ReviewResult.fromAiResponse(
          filePath: 'a.dart',
          review: technical,
        );

        expect(result.hasErrors, isFalse);
        expect(result.issues, isEmpty);
        expect(result.review, technical);
      });
    }
  });

  group('LanguageService', () {
    test('returns the text in the requested language', () {
      expect(
        LanguageService.getText('en', 'report_title'),
        contains('Code Review Report'),
      );
      expect(
        LanguageService.getText('vi', 'report_title'),
        isNot(LanguageService.getText('en', 'report_title')),
      );
    });

    test('an unknown language falls back to English', () {
      expect(
        LanguageService.getText('xx', 'report_title'),
        LanguageService.getText('en', 'report_title'),
      );
    });

    test('an unknown key comes back as the key', () {
      expect(LanguageService.getText('en', 'no_such_key'), 'no_such_key');
    });

    test('{name} placeholders are replaced', () {
      // No shipped text has a placeholder; the substitution still has to
      // leave a text without one alone.
      expect(
        LanguageService.getText('en', 'path', {'x': '1'}),
        LanguageService.getText('en', 'path'),
      );
    });

    test('every key the report uses exists in English', () {
      const used = [
        'report_title',
        'generated',
        'project',
        'total_files_reviewed',
        'section_summary',
        'section_detailed',
        'overall_results',
        'total_files',
        'files_with_issues',
        'critical_files',
        'total_issues',
        'success_rate',
        'final_verification',
        'additional_resources',
        'generated_by',
        'path',
        'priority',
        'issues_found',
        'reviewed',
      ];
      for (final key in used) {
        expect(LanguageService.getText('en', key), isNot(key), reason: key);
      }
    });

    test('every supported language translates the report (cognates aside)', () {
      // French shares a few words with English; nothing else may fall back.
      const cognates = {
        'fr': {'suggestions', 'improvements', 'score'},
      };
      const keys = [
        'report_title',
        'generated',
        'project',
        'total_files_reviewed',
        'section_summary',
        'section_detailed',
        'overall_results',
        'final_verification',
        'additional_resources',
        'generated_by',
        'total_files',
        'files_with_issues',
        'critical_files',
        'total_issues',
        'success_rate',
        'issues_found',
        'path',
        'priority',
        'reviewed',
        'suggestions',
        'improvements',
        'score',
      ];
      for (final language in CodeReviewConstants.supportedLanguages) {
        if (language == 'en') continue;
        for (final key in keys) {
          if (cognates[language]?.contains(key) ?? false) continue;
          expect(
            LanguageService.getText(language, key),
            isNot(LanguageService.getText('en', key)),
            reason: '$language / $key falls back to English',
          );
        }
      }
    });

    test('every supported language has a display name', () {
      for (final language in CodeReviewConstants.supportedLanguages) {
        expect(CodeReviewConstants.languageNames[language], isNotEmpty);
      }
    });
  });

  group('PromptService', () {
    test(
      'uses the fallback prompt when there is no review_prompt.md',
      () async {
        final prompt = await PromptService.loadReviewPrompt();

        expect(
          prompt,
          contains('Code Review Prompt for Flutter Clean Architecture'),
        );
      },
    );

    test(
      'uses review_prompt.md from the tool directory when it exists',
      () async {
        File(p.join(toolDir.path, 'review_prompt.md'))
            .writeAsStringSync('# MY RULES\n');

        expect(await PromptService.loadReviewPrompt(), '# MY RULES\n');
      },
    );

    test(
      'a review prompt names the file, its type and layer and holds the code',
      () async {
        final prompt = await PromptService.buildReviewPrompt(
          code: 'class LoginPage {}',
          filePath: 'modules/auth/feature/lib/pages/login_page.dart',
        );

        expect(
          prompt,
          contains(
            '**File Path**: modules/auth/feature/lib/pages/login_page.dart',
          ),
        );
        expect(prompt, contains('**File Type**: Page'));
        expect(prompt, contains('**Layer**: Presentation Layer'));
        expect(prompt, contains('```dart\nclass LoginPage {}\n```'));
        expect(
          prompt,
          contains('LANGUAGE: Write the entire analysis in ENGLISH'),
        );
        expect(prompt, isNot(contains('Focus specifically on')));
      },
    );

    test('focus areas are listed in the prompt', () async {
      final prompt = await PromptService.buildReviewPrompt(
        code: 'x',
        filePath: 'a.dart',
        focusAreas: ['security', 'bugs'],
      );

      expect(prompt, contains('Focus specifically on: security, bugs.'));
    });

    const languageMarkers = {
      'vi': 'TIẾNG VIỆT',
      'ja': '日本語',
      'ko': '한국어',
      'zh': '中文',
      'fr': 'FRANÇAIS',
      'de': 'DEUTSCH',
      'es': 'ESPAÑOL',
      'en': 'ENGLISH',
    };
    languageMarkers.forEach((language, marker) {
      test('the $language prompt asks for the analysis in $marker', () async {
        final prompt = await PromptService.buildReviewPrompt(
          code: 'x',
          filePath: 'a.dart',
          language: language,
        );

        expect(prompt, contains(marker));
      });
    });

    test('an unsupported language asks for English', () async {
      final prompt = await PromptService.buildReviewPrompt(
        code: 'x',
        filePath: 'a.dart',
        language: 'xx',
      );

      expect(prompt, contains('ENGLISH'));
    });

    test('a batch prompt carries every file with its type and layer', () async {
      final prompt = await PromptService.buildBatchReviewPrompt(
        filesContent: {
          'modules/a/domain/lib/user_entity.dart': 'class User {}',
          'apps/mobile/lib/main.dart': 'void main() {}',
        },
        focusAreas: ['style'],
        language: 'de',
      );

      expect(prompt, contains('Batch Review Task'));
      expect(prompt, contains('Focus specifically on: style.'));
      expect(
        prompt,
        contains('### File: modules/a/domain/lib/user_entity.dart'),
      );
      expect(prompt, contains('**Type**: Entity'));
      expect(prompt, contains('**Layer**: Domain Layer'));
      expect(prompt, contains('### File: apps/mobile/lib/main.dart'));
      expect(prompt, contains('```dart\nvoid main() {}\n```'));
      expect(prompt, contains('DEUTSCH'));
      expect(prompt, contains('Required Batch Review Output'));
    });
  });

  group('ConfigService', () {
    File configFile() => File(p.join(toolDir.path, 'code_review_config.json'));

    test('defaults when there is no config file', () {
      final config = ConfigService.getConfig();

      expect(config['reportLanguage'], 'en');
      expect(ConfigService.getBatchSize(), 5);
      expect(ConfigService.getDelayBetweenBatches(), 2000);
      expect(ConfigService.getIncludeTimestamps(), isTrue);
      expect(ConfigService.getDetailedOutput(), isTrue);
    });

    test('a partial file is merged over the defaults', () {
      configFile().writeAsStringSync(
        '{"batchSize": 3, "reportLanguage": "vi"}',
      );

      expect(ConfigService.getBatchSize(), 3);
      expect(ConfigService.getReportLanguage(), 'vi');
      expect(ConfigService.getDelayBetweenBatches(), 2000);
    });

    test('a corrupt file falls back to the defaults', () {
      configFile().writeAsStringSync('{not json');

      expect(ConfigService.getBatchSize(), 5);
      expect(ConfigService.getReportLanguage(), 'en');
    });

    test('an unsupported language in the file means English', () {
      configFile().writeAsStringSync('{"reportLanguage": "klingon"}');

      expect(ConfigService.getReportLanguage(), 'en');
    });

    test('this run\'s --language wins over the file and is not saved', () {
      configFile().writeAsStringSync('{"reportLanguage": "vi"}');

      ConfigService.languageOverride = 'ja';

      expect(ConfigService.getReportLanguage(), 'ja');
      expect(configFile().readAsStringSync(), contains('"vi"'));
    });

    test('an unsupported --language override is ignored', () {
      configFile().writeAsStringSync('{"reportLanguage": "vi"}');

      ConfigService.languageOverride = 'klingon';

      expect(ConfigService.getReportLanguage(), 'vi');
    });

    test('setters persist and keep the other keys', () async {
      configFile().writeAsStringSync('{"batchSize": 3}');

      await ConfigService.setReportLanguage('fr');
      await ConfigService.setDelayBetweenBatches(500);
      await ConfigService.setIncludeTimestamps(false);
      await ConfigService.setDetailedOutput(false);

      final saved =
          jsonDecode(configFile().readAsStringSync()) as Map<String, dynamic>;
      expect(saved['reportLanguage'], 'fr');
      expect(saved['delayBetweenBatches'], 500);
      expect(saved['includeTimestamps'], isFalse);
      expect(saved['detailedOutput'], isFalse);
      expect(saved['batchSize'], 3);
    });

    test('a saved file is indented JSON', () async {
      await ConfigService.setBatchSize(7);

      expect(configFile().readAsStringSync(), contains('\n    "batchSize": 7'));
    });

    test(
      'an unsupported language is rejected and nothing is written',
      () async {
        await expectLater(
          ConfigService.setReportLanguage('klingon'),
          throwsA(isA<ArgumentError>()),
        );
        expect(configFile().existsSync(), isFalse);
      },
    );

    for (final size in const [0, 21, -1]) {
      test('a batch size of $size is rejected', () async {
        await expectLater(
          ConfigService.setBatchSize(size),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    for (final size in const [1, 20]) {
      test('a batch size of $size is accepted', () async {
        await ConfigService.setBatchSize(size);

        expect(ConfigService.getBatchSize(), size);
      });
    }

    for (final delay in const [-1, 10001]) {
      test('a delay of $delay ms is rejected', () async {
        await expectLater(
          ConfigService.setDelayBetweenBatches(delay),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('a delay of 0 and of 10000 ms is accepted', () async {
      await ConfigService.setDelayBetweenBatches(0);
      expect(ConfigService.getDelayBetweenBatches(), 0);
      await ConfigService.setDelayBetweenBatches(10000);
      expect(ConfigService.getDelayBetweenBatches(), 10000);
    });
  });

  group('ApiKeyService', () {
    test('mask never reveals more than four characters', () {
      expect(ApiKeyService.mask('AIzaSyD-1234567890abcdef'), 'AIza…');
    });

    test('mask of a short key shows only its length', () {
      expect(ApiKeyService.mask('abc'), '*** (3 chars)');
      expect(ApiKeyService.mask(''), '*** (0 chars)');
      expect(ApiKeyService.mask('12345678901'), '*** (11 chars)');
    });

    test('--api-key wins over everything else', () {
      File(p.join(toolDir.path, '.gemini_api_key'))
          .writeAsStringSync('saved-key\n');
      final args = (ArgParser()..addOption('api-key')).parse([
        '--api-key',
        'from-arg',
      ]);

      expect(ApiKeyService.getApiKey(args), 'from-arg');
    });
  });

  group('ApiService', () {
    const key = 'AIzaSyD-secret-key-0123456789abcdefghij';

    http.Response ok(String text) => geminiReply(text);

    ApiService service(MockClient client) => ApiService(key, client: client);

    Future<String> review(ApiService api) =>
        api.reviewSingleFile(code: 'class A {}', filePath: 'lib/a.dart');

    test(
      'posts the prompt to Gemini with the key in a header, not the URL',
      () async {
        late http.Request seen;
        final api = service(
          MockClient((request) async {
            seen = request;
            return ok('REVIEW');
          }),
        );

        final text = await api.reviewSingleFile(
          code: 'class A {}',
          filePath: 'lib/a.dart',
          focusAreas: ['bugs'],
          language: 'vi',
        );

        expect(text, 'REVIEW');
        expect(seen.method, 'POST');
        expect(seen.url.toString(), CodeReviewConstants.geminiApiUrl);
        expect(seen.url.toString(), isNot(contains('key=')));
        expect(seen.headers[ApiService.apiKeyHeader], key);
        expect(seen.headers['content-type'], contains('application/json'));
        final body = jsonDecode(seen.body) as Map<String, dynamic>;
        final prompt = promptOf(seen);
        expect(prompt, contains('class A {}'));
        expect(prompt, contains('Focus specifically on: bugs.'));
        expect(prompt, contains('TIẾNG VIỆT'));
        expect(
          (body['generationConfig'] as Map)['maxOutputTokens'],
          CodeReviewConstants.maxOutputTokens,
        );
        expect(
          (body['generationConfig'] as Map)['temperature'],
          CodeReviewConstants.temperature,
        );
      },
    );

    test('a batch review sends every file in one request', () async {
      var calls = 0;
      late String prompt;
      final api = service(
        MockClient((request) async {
          calls++;
          prompt = promptOf(request);
          return ok('BATCH');
        }),
      );

      final text = await api.reviewBatch(
        filesContent: {'a.dart': 'AAA', 'b.dart': 'BBB'},
      );

      expect(text, 'BATCH');
      expect(calls, 1);
      expect(prompt, contains('### File: a.dart'));
      expect(prompt, contains('### File: b.dart'));
    });

    test('a response without candidates is reported, not thrown', () async {
      final api = service(MockClient((_) async => http.Response('{}', 200)));

      expect(await review(api), 'No response generated by API.');
    });

    test(
      'a candidate without content, parts or text says what is missing',
      () async {
        Future<String> reply(Object body) => review(
          service(
            MockClient((_) async => http.Response(jsonEncode(body), 200)),
          ),
        );

        expect(
          await reply({
            'candidates': [<String, Object>{}],
          }),
          'No content in API response candidate.',
        );
        expect(
          await reply({
            'candidates': [
              {'content': <String, Object>{}},
            ],
          }),
          'No parts in API response content.',
        );
        expect(
          await reply({
            'candidates': [
              {
                'content': {
                  'parts': [<String, Object>{}],
                },
              },
            ],
          }),
          'No text in API response part.',
        );
      },
    );

    test('a prompt blocked by Gemini throws with the reason', () async {
      final api = service(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'candidates': <Object>[],
              'promptFeedback': {'blockReason': 'SAFETY'},
            }),
            200,
          ),
        ),
      );

      await expectLater(
        review(api),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'API returned no candidates. Reason: SAFETY.',
          ),
        ),
      );
    });

    test('an unparseable 200 body is an ApiException', () async {
      final api = service(
        MockClient((_) async => http.Response('<html>', 200)),
      );

      await expectLater(
        review(api),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            startsWith('Failed to parse successful API response'),
          ),
        ),
      );
    });

    test(
      '429 is a rate limit with the Retry-After header as the delay',
      () async {
        final api = service(
          MockClient(
            (_) async => http.Response('', 429, headers: {'retry-after': '7'}),
          ),
        );

        await expectLater(
          review(api),
          throwsA(
            isA<ApiRateLimitException>().having(
              (e) => e.retryAfter,
              'retryAfter',
              7,
            ),
          ),
        );
      },
    );

    test(
      '503 is a rate limit too, and the delay can come from the body',
      () async {
        final api = service(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {'message': 'Quota. Please retry after 12 seconds.'},
              }),
              503,
            ),
          ),
        );

        await expectLater(
          review(api),
          throwsA(
            isA<ApiRateLimitException>().having(
              (e) => e.retryAfter,
              'retryAfter',
              12,
            ),
          ),
        );
      },
    );

    test('a rate limit with no hint waits 60 seconds', () async {
      final api = service(MockClient((_) async => http.Response('nope', 429)));

      await expectLater(
        review(api),
        throwsA(
          isA<ApiRateLimitException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            60,
          ),
        ),
      );
    });

    test(
      'another status is an ApiException with the status and body',
      () async {
        final api = service(
          MockClient((_) async => http.Response('{"error":"bad"}', 400)),
        );

        await expectLater(
          review(api),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 400)
                .having(
                  (e) => e.responseBody,
                  'responseBody',
                  '{"error":"bad"}',
                )
                .having((e) => '$e', 'toString', contains('(Status: 400)')),
          ),
        );
      },
    );

    test('the key is scrubbed from an error response that echoes it', () async {
      final api = service(
        MockClient(
          (_) async => http.Response('invalid key $key in request', 400),
        ),
      );

      Object? caught;
      try {
        await review(api);
      } catch (e) {
        caught = e;
      }

      expect('$caught', isNot(contains(key)));
      expect('$caught', contains('<redacted>'));
    });

    test('a network error that prints the URL never leaks the key', () async {
      final api = service(
        MockClient(
          (_) async => throw http.ClientException(
            'connection reset',
            Uri.parse('https://example.com/v1?key=$key&alt=json'),
          ),
        ),
      );

      Object? caught;
      try {
        await review(api);
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<ApiException>());
      expect('$caught', isNot(contains(key)));
      expect('$caught', contains('key=<redacted>'));
      expect('$caught', startsWith('ApiException: Failed to call Gemini API'));
    });

    test('a timeout is an ApiTimeoutException', () async {
      final api = service(
        MockClient((_) async => throw TimeoutException('too slow')),
      );

      await expectLater(review(api), throwsA(isA<ApiTimeoutException>()));
    });

    test('redact removes the key and any key= query value', () {
      final api = ApiService(key);

      expect(api.redact('a $key b'), 'a <redacted> b');
      expect(
        api.redact('https://x/y?alt=json&key=abc123&z=1'),
        'https://x/y?alt=json&key=<redacted>&z=1',
      );
      expect(api.redact('nothing to hide'), 'nothing to hide');
    });

    test('isValidApiKeyFormat wants an AIza prefix and 35 characters', () {
      expect(ApiService.isValidApiKeyFormat(key), isTrue);
      expect(ApiService.isValidApiKeyFormat('AIza-short'), isFalse);
      expect(ApiService.isValidApiKeyFormat('XXXX${'a' * 40}'), isFalse);
    });
  });

  group('BatchService', () {
    http.Response ok(String text) => geminiReply(text);

    late Directory work;
    setUp(() => work = Directory.systemTemp.createTempSync('code_review_src_'));
    tearDown(() => work.deleteSync(recursive: true));

    String source(String name, String content) {
      final file = File(p.join(work.path, name))..writeAsStringSync(content);
      return file.path;
    }

    Future<List<ReviewResult>> run(
      MockClient client,
      List<String> paths, {
      int batchSize = 2,
    }) => BatchService(ApiService('k', client: client)).reviewFilesInBatches(
      filePaths: paths,
      focusAreas: const [],
      batchSize: batchSize,
      delayBetweenBatches: Duration.zero,
    );

    test(
      'reviews every file, in batches, and keeps one result per file',
      () async {
        final seen = <String>[];
        final client = MockClient((request) async {
          final prompt = promptOf(request);
          seen.add(RegExp(r'class (\w+)').firstMatch(prompt)!.group(1)!);
          return ok('### 🚨 Issues Identified\n1. **Problem**\n');
        });
        final paths = [
          source('a.dart', 'class A {}'),
          source('b.dart', 'class B {}'),
          source('c.dart', 'class C {}'),
        ];

        final results = await run(client, paths);

        expect(results, hasLength(3));
        expect(seen..sort(), ['A', 'B', 'C']);
        expect(results.map((r) => r.filePath).toSet(), paths.toSet());
        expect(results.every((r) => r.issues.single == 'Problem'), isTrue);
      },
    );

    test(
      'a file that is missing or empty is an error result and costs no request',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return ok('fine');
        });
        final results = await run(client, [
          p.join(work.path, 'missing.dart'),
          source('empty.dart', '  \n'),
        ]);

        final byName = {for (final r in results) r.fileName: r};
        expect(calls, 0);
        expect(byName['missing.dart']!.hasErrors, isTrue);
        expect(
          byName['missing.dart']!.review,
          'File not found or could not be read',
        );
        expect(byName['empty.dart']!.hasErrors, isTrue);
        expect(byName['empty.dart']!.review, 'File is empty');
      },
    );

    test('a rate-limited file is retried and its real review replaces the placeholder', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('', 429, headers: {'retry-after': '0'})
            : ok('RETRIED REVIEW');
      });

      final results = await run(client, [source('a.dart', 'class A {}')]);

      expect(calls, 2);
      expect(results.single.review, 'RETRIED REVIEW');
      expect(results.single.hasErrors, isFalse);
    });

    test('any other failure is an error result and is not retried', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('boom', 500);
      });

      final results = await run(client, [source('a.dart', 'class A {}')]);

      expect(calls, 1);
      expect(results.single.hasErrors, isTrue);
      expect(
        results.single.review,
        startsWith('Error: ApiException: API request failed'),
      );
    });
  });

  group('ReportService', () {
    late Directory out;
    setUp(() => out = Directory.systemTemp.createTempSync('code_review_out_'));
    tearDown(() => out.deleteSync(recursive: true));

    ReviewResult result(
      String name, {
      String review = '### 🚨 Issues Identified\n',
      List<String> issues = const [],
      bool hasErrors = false,
    }) => ReviewResult(
      filePath: 'lib/$name',
      fileName: name,
      review: review,
      timestamp: DateTime(2026, 1, 2, 3, 4, 5),
      hasErrors: hasErrors,
      issues: issues,
    );

    Future<String> render(
      List<ReviewResult> results, {
      String? dir,
    }) async {
      await ReportService.generateSummaryReport(
        reviewResults: results,
        outputDir: dir ?? out.path,
      );
      final reports = Directory(dir ?? out.path)
          .listSync()
          .whereType<File>()
          .toList();
      expect(reports, hasLength(1));
      return reports.single.readAsStringSync();
    }

    test('writes one dated Markdown report', () async {
      await render([result('a.dart')]);

      final name = p.basename(out.listSync().single.path);
      expect(
        name,
        matches(
          RegExp(r'^code_review_report_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.md$'),
        ),
      );
    });

    test('creates the output directory, nested', () async {
      final nested = p.join(out.path, 'deep', 'reports');

      final text = await render([result('a.dart')], dir: nested);

      expect(text, isNotEmpty);
    });

    test('nothing is written for an empty result list', () async {
      await ReportService.generateSummaryReport(
        reviewResults: [],
        outputDir: p.join(out.path, 'none'),
      );

      expect(Directory(p.join(out.path, 'none')).existsSync(), isFalse);
    });

    test(
      'the summary counts files, issues, critical files and success rate',
      () async {
        final text = await render([
          result('clean.dart'),
          result('minor.dart', issues: ['one']),
          result('many.dart', issues: ['1', '2', '3', '4']),
          result('critical.dart', issues: ['x'], hasErrors: true),
        ]);

        expect(text, contains('# 📋 Code Review Report'));
        expect(text, contains('**Total Files Reviewed:** 4'));
        expect(text, contains('| **Total Files** | 4 |'));
        expect(text, contains('| **Files with Issues** | 3 |'));
        expect(text, contains('| **Critical Files** | 1 |'));
        expect(text, contains('| **Total Issues** | 6 |'));
        expect(text, contains('| **Success Rate** | 25.0% |'));
        expect(text, contains('| 🔴 **High** | 2 |'));
        expect(text, contains('| 🟡 **Medium** | 1 |'));
        expect(text, contains('| 🟢 **Clean** | 1 |'));
      },
    );

    test('files are detailed highest priority first', () async {
      final text = await render([
        result('clean.dart'),
        result('critical.dart', issues: ['x'], hasErrors: true),
        result('minor.dart', issues: ['one']),
      ]);

      expect(
        text.indexOf('## 📄 critical.dart'),
        lessThan(text.indexOf('## 📄 minor.dart')),
      );
      expect(
        text.indexOf('## 📄 minor.dart'),
        lessThan(text.indexOf('## 📄 clean.dart')),
      );
      expect(text, contains('**Priority:** 🔴 HIGH'));
      expect(text, contains('**Priority:** 🟡 LOW'));
      expect(text, contains('**Priority:** 🟢 CLEAN'));
      expect(text, contains('**Path:** `lib/critical.dart`'));
    });

    test('the most common issues are ranked', () async {
      final text = await render([
        result('a.dart', issues: ['Missing dispose']),
        result('b.dart', issues: ['Missing dispose', 'Other']),
      ]);

      expect(text, contains('1. **Missing dispose** (2 occurrences)'));
      expect(text, contains('2. **Other** (1 occurrences)'));
    });

    test('a technical error is shown as one, not as a code issue', () async {
      final text = await render([
        result(
          'a.dart',
          review: 'Error: ApiException: boom',
          hasErrors: true,
          issues: ['Review error: boom'],
        ),
      ]);

      expect(text, contains('⚪ UNKNOWN (Technical Error)'));
      expect(text, contains('### ⚠️ Technical Error'));
      expect(text, contains('```\nError: ApiException: boom\n```'));
    });

    test('the AI\'s own title line is not repeated in the detail', () async {
      final text = await render([
        result(
          'a.dart',
          review: '## 📝 Code Review: `a.dart`\n\nBody of the review.',
        ),
      ]);

      expect(text, contains('Body of the review.'));
      expect(text, isNot(contains('## 📝 Code Review:')));
    });

    test('ends with the verification commands', () async {
      final text = await render([result('a.dart')]);

      expect(text, contains('# ✅ FINAL VERIFICATION'));
      expect(text, contains('flutter analyze --fatal-infos'));
      expect(text, contains('*Generated by Code Review Tool*'));
    });

    test(
      'is written in the configured language, without a timestamp if asked',
      () async {
        File(p.join(toolDir.path, 'code_review_config.json')).writeAsStringSync(
          '{"reportLanguage": "vi", "includeTimestamps": false}',
        );

        final text = await render([result('a.dart')]);

        expect(
          text,
          contains('# ${LanguageService.getText('vi', 'report_title')}'),
        );
        expect(
          text,
          isNot(contains('**${LanguageService.getText('vi', 'generated')}:**')),
        );
        expect(
          text,
          contains('**${LanguageService.getText('vi', 'project')}:**'),
        );
      },
    );

    test('has a generated timestamp by default', () async {
      final text = await render([result('a.dart')]);

      expect(text, contains('**Generated:**'));
    });
  });

  group('FileService', () {
    late Directory work;
    setUp(
      () => work = Directory.systemTemp.createTempSync('code_review_files_'),
    );
    tearDown(() => work.deleteSync(recursive: true));

    test('reads a file, or null when it does not exist', () async {
      final file = File(p.join(work.path, 'a.dart'))
        ..writeAsStringSync('class A {}');

      expect(await FileService.readFileContent(file.path), 'class A {}');
      expect(
        await FileService.readFileContent(p.join(work.path, 'no.dart')),
        isNull,
      );
    });

    test('reads several files and leaves out the missing ones', () async {
      final a = File(p.join(work.path, 'a.dart'))..writeAsStringSync('A');
      final missing = p.join(work.path, 'missing.dart');

      final content = await FileService.readMultipleFiles([a.path, missing]);

      expect(content, {a.path: 'A'});
    });

    test(
      'writes a file, creating its directories, and overwrites it',
      () async {
        final path = p.join(work.path, 'x', 'y', 'report.md');

        await FileService.writeFile(path, 'one');
        await FileService.writeFile(path, 'two');

        expect(File(path).readAsStringSync(), 'two');
      },
    );

    test('a write that cannot succeed is reported with the path', () async {
      final blocker = File(p.join(work.path, 'file'))..writeAsStringSync('x');

      await expectLater(
        FileService.writeFile(p.join(blocker.path, 'inside.md'), 'x'),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('Failed to write file'),
          ),
        ),
      );
    });

    test('fileExists and ensureDirectoryExists', () async {
      final dir = p.join(work.path, 'made', 'here');

      expect(await FileService.fileExists(dir), isFalse);
      await FileService.ensureDirectoryExists(dir);
      await FileService.ensureDirectoryExists(dir);

      expect(Directory(dir).existsSync(), isTrue);
    });
  });
}

/// A Gemini 200 response whose first candidate says [text] (UTF-8 on the
/// wire, as the real API sends it).
http.Response geminiReply(String text) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The prompt text a recorded Gemini request carried.
String promptOf(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final contents = body['contents'] as List<dynamic>;
  final parts =
      (contents.single as Map<String, dynamic>)['parts'] as List<dynamic>;
  return (parts.first as Map<String, dynamic>)['text'] as String;
}
