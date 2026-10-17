import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' hide test;
import 'package:platform_app_shell/platform_app_shell.dart';

class _Plain {}

class _NeedsPlain {
  _NeedsPlain(this.dependency);

  final _Plain dependency;
}

class _Optional {
  _Optional(this.session);

  final String? session;
}

class _Detail {
  _Detail(this.id);

  final String id;
}

class _Two {
  _Two(this.id, this.page);

  final String id;
  final int page;
}

class _Async {}

class _AsyncBroken {}

class _Cached {}

class _Missing {
  _Missing(this.dependency);

  final _Plain dependency;
}

/// A graph registered through `injectable`'s own helper, the way a generated
/// `init` does, with a [FactoryRecorder] standing in for the locator.
Future<(FactoryRecorder, GetIt)> _boot(
  void Function(GetItHelper gh) wire,
) async {
  final inner = GetIt.asNewInstance();
  final recorder = FactoryRecorder(inner);
  final gh = GetItHelper(recorder, 'dev');
  wire(gh);
  return (recorder, inner);
}

void main() {
  test('a plain factory, one with a dependency and one with a nullable '
      'parameter are built', () async {
    final (recorder, _) = await _boot((gh) {
      gh.lazySingleton<_Plain>(_Plain.new);
      gh.factory<_NeedsPlain>(() => _NeedsPlain(gh<_Plain>()));
      gh.factoryParam<_Optional, String?, dynamic>(
        (session, _) => _Optional(session),
      );
      gh.factory<_Cached>(_Cached.new);
    });

    final report = await recorder.buildEvery();
    expect(report.problems, isEmpty, reason: report.explain());
    expect(
      report.built,
      unorderedEquals(['_NeedsPlain', '_Optional', '_Cached']),
    );
    expect(recorder.factoryNames, hasLength(3));
  });

  test(
    'an async factory is awaited, a throwing one is F02 naming the type',
    () async {
      final (recorder, _) = await _boot((gh) {
        gh.factoryAsync<_Async>(() async => _Async());
        gh.factoryAsync<_AsyncBroken>(
          () async => throw StateError('no network'),
        );
        gh.factoryParamAsync<_Async, String?, dynamic>(
          (id, _) async => _Async(),
          instanceName: 'withParam',
        );
      });

      final report = await recorder.buildEvery();
      expect(report.built, ['_Async', '_Async']);
      expect(report.problems.map((p) => p.id), ['F02']);
      expect(report.problems.single.type, '_AsyncBroken');
      expect(report.problems.single.message, contains('async factory'));
      expect(report.problems.single.message, contains('no network'));
    },
  );

  test('a factory whose dependency is not registered is F02 naming the '
      'factory, not the dependency', () async {
    final (recorder, _) = await _boot((gh) {
      gh.factory<_Missing>(() => _Missing(gh<_Plain>()));
    });

    final report = await recorder.buildEvery();
    expect(report.problems.single.id, 'F02');
    expect(report.problems.single.type, '_Missing');
    expect(report.problems.single.message, contains('_Plain'));
  });

  group('a factory with a non-nullable @factoryParam', () {
    Future<FactoryRecorder> boot() async {
      final (recorder, _) = await _boot((gh) {
        gh.factoryParam<_Detail, String, dynamic>((id, _) => _Detail(id));
        gh.factoryParam<_Two, String, int>(_Two.new);
        gh.factory<_Plain>(_Plain.new);
      });
      return recorder;
    }

    test(
      'is F01 with the type and the parameter types, unless listed',
      () async {
        final report = await (await boot()).buildEvery();
        expect(report.problems.map((p) => p.id), ['F01', 'F01']);
        expect(report.problems.map((p) => p.type), ['_Detail', '_Two']);
        expect(report.problems.first.message, contains('String'));
        expect(report.problems.last.message, contains('String, int'));
        expect(report.problems.first.message, contains('notBuilt'));
        // The way out the message names exists.
        expect(report.problems.first.message, isNot(contains('by hand')));
        expect(report.built, ['_Plain']);
      },
    );

    test('is skipped, with its reason, when listed', () async {
      final report = await (await boot()).buildEvery(
        notBuilt: {
          '_Detail': 'the detail route always passes the id',
          '_Two': 'the list route passes the id and the page',
        },
      );
      expect(report.problems, isEmpty, reason: report.explain());
      expect(report.skipped.keys, ['_Detail', '_Two']);
      expect(report.skipped['_Detail'], contains('detail route'));
      expect(report.built, ['_Plain']);
    });

    test('an entry with no reason is F04, and the factory is not skipped '
        'silently', () async {
      final report = await (await boot()).buildEvery(
        notBuilt: {
          '_Detail': 'x',
          '_Two': 'the list route passes the id and the page',
        },
      );
      expect(report.problems.map((p) => p.id), ['F04']);
      expect(report.problems.single.type, '_Detail');
    });
  });

  test('an entry that names no factory, or a factory that needs no argument, '
      'is F03', () async {
    final (recorder, _) = await _boot((gh) {
      gh.factory<_Plain>(_Plain.new);
    });
    final report = await recorder.buildEvery(
      notBuilt: {
        'Gone': 'a detail controller that was deleted last week',
        '_Plain': 'this one never needed an argument at all',
      },
    );
    expect(report.problems.map((p) => p.id), ['F03', 'F03']);
    expect(report.problems.map((p) => p.type), ['Gone', '_Plain']);
    expect(report.problems.first.message, contains('Remove the entry'));
    expect(report.built, ['_Plain']);
  });

  test(
    'the real locator ends up with everything the helper registered',
    () async {
      final (_, inner) = await _boot((gh) {
        gh.lazySingleton<_Plain>(_Plain.new);
        gh.factory<_NeedsPlain>(() => _NeedsPlain(gh<_Plain>()));
        gh.factoryParam<_Detail, String, dynamic>((id, _) => _Detail(id));
      });
      expect(inner.isRegistered<_Plain>(), isTrue);
      expect(inner<_NeedsPlain>().dependency, same(inner<_Plain>()));
      expect(inner<_Detail>(param1: '42').id, '42');
    },
  );

  test('an unforwarded member fails loudly instead of doing nothing', () {
    final recorder = FactoryRecorder(GetIt.asNewInstance());
    expect(
      recorder.pushNewScope,
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('pushNewScope'),
        ),
      ),
    );
  });
}
