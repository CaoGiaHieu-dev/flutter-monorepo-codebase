import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `BlocViewState<T>` is the optional four-state helper BLoC features emit.
/// Its one piece of logic is the `data` getter; the rest is the Freezed
/// contract features switch on.
class _CounterCubit extends BaseCubit<BlocViewState<int>> {
  _CounterCubit() : super(const BlocViewState.initial());

  void load(int value) {
    emit(const BlocViewState.loading());
    emit(BlocViewState.success(value));
  }

  void fail(AppFailure failure) => emit(BlocViewState.error(failure));
}

void main() {
  const failure = NetworkFailure<dynamic>(message: 'offline', code: 1005);

  group('data', () {
    test('is the payload of a success', () {
      expect(const BlocViewState<int>.success(3).data, 3);
    });

    test('is null in every other state', () {
      for (final state in const [
        BlocViewState<int>.initial(),
        BlocViewState<int>.loading(),
        BlocViewState<int>.error(failure),
      ]) {
        expect(state.data, isNull, reason: '$state');
      }
    });
  });

  test('when dispatches on every state and error carries its failure', () {
    String describe(BlocViewState<int> s) => s.when(
      initial: () => 'initial',
      loading: () => 'loading',
      success: (data) => 'success:$data',
      error: (error) => 'error:${error.code}',
    );

    expect(describe(const BlocViewState.initial()), 'initial');
    expect(describe(const BlocViewState.loading()), 'loading');
    expect(describe(const BlocViewState.success(1)), 'success:1');
    expect(describe(const BlocViewState.error(failure)), 'error:1005');
  });

  test('states compare by value', () {
    expect(
      const BlocViewState<int>.success(1),
      const BlocViewState<int>.success(1),
    );
    expect(
      const BlocViewState<int>.success(1),
      isNot(const BlocViewState<int>.success(2)),
    );
    expect(
      const BlocViewState<int>.error(failure),
      const BlocViewState<int>.error(
        NetworkFailure(message: 'offline', code: 1005),
      ),
    );
  });

  group('BaseCubit', () {
    test('emits through BlocViewState in order', () async {
      final cubit = _CounterCubit();
      addTearDown(cubit.close);
      final states = <BlocViewState<int>>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(sub.cancel);

      cubit.load(5);
      cubit.fail(failure);
      await pumpEventQueue();

      expect(states, const [
        BlocViewState<int>.loading(),
        BlocViewState<int>.success(5),
        BlocViewState<int>.error(failure),
      ]);
    });
  });
}
