import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `emitResult` is the BLoC branch's `executeOperation`: it turns a
/// `Result<R>` into `BlocViewState<T>` emissions. These tests pin each row of
/// its documented table, for the Bloc and the Cubit mixin alike.

const _failure = NetworkFailure<dynamic>(message: 'offline', code: 1005);

class _Load {
  const _Load(this.run, {this.showLoading = true});
  final Future<Result<int>> Function() run;
  final bool showLoading;
}

class _NullableLoad {
  const _NullableLoad(this.run);
  final Future<Result<int>> Function() run;
}

class _CountBloc extends BaseBloc<Object, BlocViewState<int>>
    with BlocResultMixin<int> {
  _CountBloc({BlocViewState<int> initial = const BlocViewState.initial()})
    : super(initial) {
    on<_Load>(
      (event, emit) => emitResult(
        emit,
        event.run,
        showLoading: event.showLoading,
        onSuccess: successes.add,
        onFailure: failures.add,
      ),
    );
  }

  final successes = <int?>[];
  final failures = <AppFailure>[];
  final reported = <Object>[];

  @override
  void onError(Object error, StackTrace stackTrace) {
    reported.add(error);
    super.onError(error, stackTrace);
  }
}

class _NullableBloc extends BaseBloc<Object, BlocViewState<int?>>
    with BlocResultMixin<int?> {
  _NullableBloc() : super(const BlocViewState.initial()) {
    on<_NullableLoad>((event, emit) => emitResult(emit, event.run));
  }
}

/// The payload is a `String` the state carries as its length.
class _LengthCubit extends BaseCubit<BlocViewState<int>>
    with CubitResultMixin<int> {
  _LengthCubit() : super(const BlocViewState.initial());

  Future<void> load(Future<Result<String>> Function() run) =>
      emitResult(run, convert: (text) => text.length);

  Future<void> loadUnconverted(Future<Result<String>> Function() run) =>
      emitResult(run);
}

/// Records every state [bloc] emits until the test ends.
List<S> _record<S>(BlocBase<S> bloc) {
  final states = <S>[];
  final sub = bloc.stream.listen(states.add);
  addTearDown(sub.cancel);
  addTearDown(bloc.close);
  return states;
}

Future<Result<int>> _value(Result<int> result) async => result;

void main() {
  group('BlocResultMixin.emitResult', () {
    test('success: loading, then success(data), then onSuccess', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);

      bloc.add(_Load(() => _value(const Result.success(7))));
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.success(7),
      ]);
      expect(bloc.successes, [7]);
      expect(bloc.failures, isEmpty);
    });

    test('failure: loading, then error(failure), then onFailure', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);

      bloc.add(_Load(() => _value(const Result.failure(_failure))));
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.error(_failure),
      ]);
      expect(bloc.failures, [_failure]);
      expect(bloc.successes, isEmpty);
    });

    test('success(null) on a non-nullable T settles to initial', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);

      bloc.add(_Load(() => _value(const Result.success())));
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.initial(),
      ]);
      expect(bloc.successes, [null]);
    });

    test('success(null) on a nullable T is success(null)', () async {
      final bloc = _NullableBloc();
      final states = _record(bloc);

      bloc.add(_NullableLoad(() => _value(const Result.success())));
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int?>.loading(),
        BlocViewState<int?>.success(null),
      ]);
    });

    for (final (name, result) in [
      ('none', const Result<int>.none()),
      ('cancel', const Result<int>.cancel()),
    ]) {
      test(
        '$name: undoes its own loading, restoring the prior state',
        () async {
          final bloc = _CountBloc(
            initial: const BlocViewState.error(_failure),
          );
          final states = _record(bloc);

          bloc.add(_Load(() => _value(result)));
          await pumpEventQueue();

          expect(states, const [
            BlocViewState<int>.loading(),
            BlocViewState<int>.error(_failure),
          ]);
          expect(bloc.successes, isEmpty);
          expect(bloc.failures, isEmpty);
        },
      );

      test('$name without loading emits nothing', () async {
        final bloc = _CountBloc();
        final states = _record(bloc);

        bloc.add(_Load(() => _value(result), showLoading: false));
        await pumpEventQueue();

        expect(states, isEmpty);
        expect(bloc.state, const BlocViewState<int>.initial());
      });
    }

    test('skips loading while a success is on screen (refresh)', () async {
      final bloc = _CountBloc(initial: const BlocViewState.success(1));
      final states = _record(bloc);

      bloc.add(_Load(() => _value(const Result.success(2))));
      await pumpEventQueue();

      expect(states, const [BlocViewState<int>.success(2)]);
    });

    test('showLoading: false emits only the outcome', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);

      bloc.add(
        _Load(() => _value(const Result.success(3)), showLoading: false),
      );
      await pumpEventQueue();

      expect(states, const [BlocViewState<int>.success(3)]);
    });

    test('a throwing operation settles to error and reaches onError', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);
      final boom = StateError('boom');

      bloc.add(_Load(() async => throw boom));
      await pumpEventQueue();

      expect(states, hasLength(2));
      expect(states.first, const BlocViewState<int>.loading());
      final failure = states.last.maybeWhen(
        error: (f) => f,
        orElse: () => null,
      );
      // ErrorHandler's mapping for an error nobody classified.
      expect(failure, isA<ServerFailure<dynamic>>());
      expect(bloc.failures, [failure]);
      expect(bloc.reported, [boom]);
    });

    test('emits nothing once the bloc closed while running', () async {
      final bloc = _CountBloc();
      final states = _record(bloc);
      final gate = Completer<Result<int>>();

      bloc.add(_Load(() => gate.future));
      await pumpEventQueue();
      final closing = bloc.close();
      gate.complete(const Result.success(9));
      await closing;

      expect(states, const [BlocViewState<int>.loading()]);
      expect(bloc.successes, isEmpty);
    });

    test('emits nothing once a restartable handler was replaced', () async {
      final gates = <Completer<Result<int>>>[];
      final bloc = _RestartableBloc(gates);
      final states = _record(bloc);

      bloc.add(const _Tick());
      await pumpEventQueue();
      bloc.add(const _Tick());
      await pumpEventQueue();
      gates[0].complete(const Result.success(1)); // superseded
      gates[1].complete(const Result.success(2));
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.success(2),
      ]);
    });
  });

  group('CubitResultMixin.emitResult', () {
    test('converts the payload through convert', () async {
      final cubit = _LengthCubit();
      final states = _record(cubit);

      await cubit.load(() async => const Result.success('four'));

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.success(4),
      ]);
    });

    test('a payload of another type without convert is a StateError', () {
      final cubit = _LengthCubit();
      _record(cubit);

      expect(
        cubit.loadUnconverted(() async => const Result.success('four')),
        throwsStateError,
      );
    });

    test('emits nothing once closed', () async {
      final cubit = _LengthCubit();
      final states = _record(cubit);
      await cubit.close();

      await cubit.load(() async => const Result.success('x'));

      expect(states, isEmpty);
    });
  });
}

class _Tick {
  const _Tick();
}

/// Each `_Tick` waits on the next of [gates]; a newer tick cancels the older.
class _RestartableBloc extends BaseBloc<_Tick, BlocViewState<int>>
    with BlocResultMixin<int> {
  _RestartableBloc(List<Completer<Result<int>>> gates)
    : super(const BlocViewState.initial()) {
    on<_Tick>((event, emit) {
      final gate = Completer<Result<int>>();
      gates.add(gate);
      return emitResult(emit, () => gate.future);
    }, transformer: _restartable());
  }
}

/// `bloc_concurrency`'s `restartable()`, inlined (the package is not a
/// dependency): a new event cancels the handler still running, which is what
/// flips that handler's `emit.isDone`.
EventTransformer<E> _restartable<E>() => (events, mapper) {
  final controller = StreamController<E>();
  StreamSubscription<E>? outer;
  StreamSubscription<E>? inner;
  controller
    ..onListen = () {
      outer = events.listen((event) {
        unawaited(inner?.cancel());
        inner = mapper(event).listen(controller.add);
      }, onDone: controller.close);
    }
    ..onCancel = () async {
      await inner?.cancel();
      await outer?.cancel();
    };
  return controller.stream;
};
