import 'package:get_it/get_it.dart';

/// Builds every `@injectable` factory of a dependency graph once, so a factory
/// that cannot be built fails a test instead of the screen that first asks for
/// it (RULE-63).
///
/// GetIt can call every factory itself (`findAll(callFactories: true)`), but
/// only with `null` arguments, only the synchronous ones, and as one
/// all-or-nothing call that names no registration when it throws. A factory
/// with a non-nullable `@factoryParam` — a detail screen's controller that
/// needs the id the route passes — is correct code and cannot be built that
/// way. So the boot is watched instead: [FactoryRecorder] stands in for the
/// locator while `configureDependencies` registers the graph, remembers each
/// factory it is handed (with its type, its parameters and whether it is
/// async), and forwards everything to the real one. [FactoryRecorder.buildEvery]
/// then builds each, one by one:
///
/// - a plain factory, and one whose parameters are all nullable, is called
///   with `null` for each parameter (`HomeProfileBloc`'s `ISessionState?`);
/// - an async factory is awaited;
/// - a factory with a non-nullable `@factoryParam` cannot be called without
///   one, so it is built only when the smoke test lists it in `notBuilt` — by
///   type name, with the reason — and is otherwise `F01`;
/// - whatever a factory throws is `F02`, with the type that threw.
///
/// ```dart
/// final recorder = FactoryRecorder(getIt);
/// await configureDependencies(environment: flavor.name, locator: recorder);
/// final report = await recorder.buildEvery(notBuilt: _notBuilt);
/// expect(report.problems, isEmpty, reason: report.explain());
/// ```
///
/// What it implements is what injectable's `GetItHelper` calls (registration,
/// `get`, `getAsync`, `isRegistered`); any other member throws, so a GetIt
/// upgrade that makes the helper call something new fails loudly here and not
/// silently.
final class FactoryRecorder implements GetIt {
  /// Wraps [inner], the locator the graph really registers into.
  FactoryRecorder(this._inner);

  final GetIt _inner;
  final List<_RecordedFactory> _factories = [];

  /// The type names of every factory registered so far.
  List<String> get factoryNames => [for (final f in _factories) f.name];

  // ---- the factories: recorded, then registered for real -------------------

  @override
  void registerFactory<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(_RecordedFactory(T, instanceName));
    _inner.registerFactory<T>(factoryFunc, instanceName: instanceName);
  }

  @override
  void registerCachedFactory<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(_RecordedFactory(T, instanceName, cached: true));
    _inner.registerCachedFactory<T>(factoryFunc, instanceName: instanceName);
  }

  @override
  void registerFactoryParam<T extends Object, P1, P2>(
    FactoryFuncParam<T, P1, P2> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(
      _RecordedFactory(
        T,
        instanceName,
        required: [
          if (<P1?>[] is! List<P1>) '$P1',
          if (<P2?>[] is! List<P2>) '$P2',
        ],
      ),
    );
    _inner.registerFactoryParam<T, P1, P2>(
      factoryFunc,
      instanceName: instanceName,
    );
  }

  @override
  void registerCachedFactoryParam<T extends Object, P1, P2>(
    FactoryFuncParam<T, P1, P2> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(
      _RecordedFactory(
        T,
        instanceName,
        cached: true,
        required: [
          if (<P1?>[] is! List<P1>) '$P1',
          if (<P2?>[] is! List<P2>) '$P2',
        ],
      ),
    );
    _inner.registerCachedFactoryParam<T, P1, P2>(
      factoryFunc,
      instanceName: instanceName,
    );
  }

  @override
  void registerFactoryAsync<T extends Object>(
    FactoryFuncAsync<T> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(_RecordedFactory(T, instanceName, async: true));
    _inner.registerFactoryAsync<T>(factoryFunc, instanceName: instanceName);
  }

  @override
  void registerCachedFactoryAsync<T extends Object>(
    FactoryFuncAsync<T> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(
      _RecordedFactory(T, instanceName, async: true, cached: true),
    );
    _inner.registerCachedFactoryAsync<T>(
      factoryFunc,
      instanceName: instanceName,
    );
  }

  // The factory function types its parameters `P1?`, `P2?`, but GetIt checks
  // the arguments against `P1` and `P2` themselves: a non-nullable one is as
  // required here as in a synchronous factory.
  @override
  void registerFactoryParamAsync<T extends Object, P1, P2>(
    FactoryFuncParamAsync<T, P1?, P2?> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(
      _RecordedFactory(
        T,
        instanceName,
        async: true,
        required: [
          if (<P1?>[] is! List<P1>) '$P1',
          if (<P2?>[] is! List<P2>) '$P2',
        ],
      ),
    );
    _inner.registerFactoryParamAsync<T, P1, P2>(
      factoryFunc,
      instanceName: instanceName,
    );
  }

  @override
  void registerCachedFactoryParamAsync<T extends Object, P1, P2>(
    FactoryFuncParamAsync<T, P1?, P2?> factoryFunc, {
    String? instanceName,
  }) {
    _factories.add(
      _RecordedFactory(
        T,
        instanceName,
        async: true,
        cached: true,
        required: [
          if (<P1?>[] is! List<P1>) '$P1',
          if (<P2?>[] is! List<P2>) '$P2',
        ],
      ),
    );
    _inner.registerCachedFactoryParamAsync<T, P1, P2>(
      factoryFunc,
      instanceName: instanceName,
    );
  }

  // ---- everything else the boot does: forwarded -----------------------------

  @override
  T registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool? signalsReady,
    DisposingFunc<T>? dispose,
  }) => _inner.registerSingleton<T>(
    instance,
    instanceName: instanceName,
    signalsReady: signalsReady,
    dispose: dispose,
  );

  @override
  void registerSingletonAsync<T extends Object>(
    FactoryFuncAsync<T> factoryFunc, {
    String? instanceName,
    Iterable<Type>? dependsOn,
    bool? signalsReady,
    DisposingFunc<T>? dispose,
    void Function(T instance)? onCreated,
  }) => _inner.registerSingletonAsync<T>(
    factoryFunc,
    instanceName: instanceName,
    dependsOn: dependsOn,
    signalsReady: signalsReady,
    dispose: dispose,
    onCreated: onCreated,
  );

  @override
  void registerSingletonWithDependencies<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
    required Iterable<Type>? dependsOn,
    bool? signalsReady,
    DisposingFunc<T>? dispose,
  }) => _inner.registerSingletonWithDependencies<T>(
    factoryFunc,
    instanceName: instanceName,
    dependsOn: dependsOn,
    signalsReady: signalsReady,
    dispose: dispose,
  );

  @override
  void registerLazySingleton<T extends Object>(
    FactoryFunc<T> factoryFunc, {
    String? instanceName,
    DisposingFunc<T>? dispose,
    void Function(T instance)? onCreated,
    bool useWeakReference = false,
  }) => _inner.registerLazySingleton<T>(
    factoryFunc,
    instanceName: instanceName,
    dispose: dispose,
    onCreated: onCreated,
    useWeakReference: useWeakReference,
  );

  @override
  void registerLazySingletonAsync<T extends Object>(
    FactoryFuncAsync<T> factoryFunc, {
    String? instanceName,
    DisposingFunc<T>? dispose,
    void Function(T instance)? onCreated,
    bool useWeakReference = false,
  }) => _inner.registerLazySingletonAsync<T>(
    factoryFunc,
    instanceName: instanceName,
    dispose: dispose,
    onCreated: onCreated,
    useWeakReference: useWeakReference,
  );

  @override
  bool isRegistered<T extends Object>({
    Object? instance,
    String? instanceName,
    Type? type,
  }) => _inner.isRegistered<T>(
    instance: instance,
    instanceName: instanceName,
    type: type,
  );

  @override
  T get<T extends Object>({
    dynamic param1,
    dynamic param2,
    String? instanceName,
    Type? type,
  }) => _inner.get<T>(
    param1: param1,
    param2: param2,
    instanceName: instanceName,
    type: type,
  );

  @override
  T? maybeGet<T extends Object>({
    dynamic param1,
    dynamic param2,
    String? instanceName,
    Type? type,
  }) => _inner.maybeGet<T>(
    param1: param1,
    param2: param2,
    instanceName: instanceName,
    type: type,
  );

  @override
  T call<T extends Object>({
    String? instanceName,
    dynamic param1,
    dynamic param2,
    Type? type,
  }) => _inner.call<T>(
    instanceName: instanceName,
    param1: param1,
    param2: param2,
    type: type,
  );

  @override
  Future<T> getAsync<T extends Object>({
    String? instanceName,
    dynamic param1,
    dynamic param2,
    Type? type,
  }) => _inner.getAsync<T>(
    instanceName: instanceName,
    param1: param1,
    param2: param2,
    type: type,
  );

  @override
  void enableRegisteringMultipleInstancesOfOneType() =>
      _inner.enableRegisteringMultipleInstancesOfOneType();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'FactoryRecorder forwards only what injectable\'s GetItHelper calls; '
    '`${invocation.memberName}` is not one of them. Call it on the real '
    'locator.',
  );

  // ---- building --------------------------------------------------------------

  /// Builds every factory recorded so far, one at a time, and reports what
  /// could not be.
  ///
  /// [notBuilt] names, by type (`DetailBloc`), the factories this check does
  /// not build, each with the reason — in practice a factory with a
  /// non-nullable `@factoryParam`, which only the screen that creates it can
  /// supply. An entry has to be earned: a type that is not a recorded factory,
  /// that needs no argument (so it is built after all), or without a reason
  /// (at least 12 characters) is itself a problem, so the list cannot rot.
  Future<FactoryReport> buildEvery({
    Map<String, String> notBuilt = const {},
  }) async {
    final built = <String>[];
    final skipped = <String, String>{};
    final problems = <FactoryProblem>[];

    final byName = <String, List<_RecordedFactory>>{};
    for (final f in _factories) {
      (byName[f.name] ??= []).add(f);
    }

    for (final entry in notBuilt.entries) {
      final matches = byName[entry.key];
      if (entry.value.trim().length < 12) {
        problems.add(
          FactoryProblem(
            'F04',
            entry.key,
            'is listed in `notBuilt` with no reason. Say why this factory is '
                'not built here (at least a sentence).',
          ),
        );
      } else if (matches == null) {
        problems.add(
          FactoryProblem(
            'F03',
            entry.key,
            'is listed in `notBuilt` but is not a factory the graph '
                'registers (renamed, deleted, or registered for another '
                'environment). Remove the entry.',
          ),
        );
      } else if (matches.every((f) => f.required.isEmpty)) {
        problems.add(
          FactoryProblem(
            'F03',
            entry.key,
            'is listed in `notBuilt` but needs no argument: it is built. '
                'Remove the entry.',
          ),
        );
      }
    }

    for (final factory in _factories) {
      final name = factory.name;
      if (factory.required.isNotEmpty) {
        final reason = notBuilt[name];
        if (reason != null && reason.trim().length >= 12) {
          skipped[name] = reason;
        } else if (!notBuilt.containsKey(name)) {
          problems.add(
            FactoryProblem(
              'F01',
              name,
              'takes a non-nullable @factoryParam '
                  '(${factory.required.join(', ')}), and this check calls '
                  'every factory without arguments. If the screen that creates '
                  'it always passes one, list `$name` in `notBuilt` with the '
                  'reason; otherwise make the parameter nullable.',
            ),
          );
        }
        continue;
      }
      try {
        // `type:` builds by the Type object, the registered one — with `null`
        // for the parameters, which a factory without any ignores.
        if (factory.async) {
          await _inner.getAsync<Object>(
            type: factory.type,
            instanceName: factory.instanceName,
          );
        } else {
          _inner.get<Object>(
            type: factory.type,
            instanceName: factory.instanceName,
          );
        }
        built.add(name);
      } on Object catch (error) {
        problems.add(
          FactoryProblem(
            'F02',
            name,
            '${factory.async ? 'async factory ' : ''}threw while being '
                'built: $error',
          ),
        );
      }
    }
    return FactoryReport(built, skipped, problems);
  }
}

/// One factory the recorder was handed.
final class _RecordedFactory {
  _RecordedFactory(
    this.type,
    this.instanceName, {
    this.async = false,
    this.cached = false,
    this.required = const [],
  });

  final Type type;
  final String? instanceName;
  final bool async;
  final bool cached;

  /// The non-nullable parameter types: calling the factory needs a value for
  /// each.
  final List<String> required;

  String get name => '$type';
}

/// A factory that could not be built, or an entry of `notBuilt` that should not
/// be there.
final class FactoryProblem {
  const FactoryProblem(this.id, this.type, this.message);

  /// `F01` a non-nullable `@factoryParam` and no `notBuilt` entry · `F02` the
  /// factory threw · `F03` a `notBuilt` entry that matches no such factory, or
  /// one that is built · `F04` a `notBuilt` entry with no reason.
  final String id;

  /// The type name the problem is about.
  final String type;
  final String message;

  @override
  String toString() => '$id `$type` $message';
}

/// What [FactoryRecorder.buildEvery] did.
final class FactoryReport {
  const FactoryReport(this.built, this.skipped, this.problems);

  /// Type names of the factories that were built.
  final List<String> built;

  /// Type name -> the reason it was not built (the `notBuilt` entries).
  final Map<String, String> skipped;
  final List<FactoryProblem> problems;

  /// One problem per line, for a test's `reason:`.
  String explain() => problems.isEmpty
      ? '${built.length} factories built, ${skipped.length} skipped'
      : problems.join('\n');
}
