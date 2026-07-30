import 'package:core_common/core_common.dart';
import 'package:domain_core/domain_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'view_state_model_test.dart';

/// Minimal provider for operation / state tests.
class TestProvider extends BaseProvider<String> {
  TestProvider() : super();

  Future<void> runSuccessOperation(
    String resultData, {
    bool showLoading = true,
  }) async {
    await executeOperation(
      OperationConfig(
        operation: () async => Result.success(resultData),
        showLoading: showLoading,
      ),
    );
  }

  Future<void> runVoidSuccessOperation() async {
    await executeOperation(
      OperationConfig(
        operation: () async => const Result.success(null),
        showLoading: false,
      ),
    );
  }

  Future<void> runVoidSuccessAndClear() async {
    await executeOperation(
      OperationConfig(
        operation: () async => const Result.success(null),
        showLoading: false,
        onSuccess: (_) async {
          updateState(
            state: const ViewState.success(),
            data: null,
            retainOldData: false,
          );
        },
      ),
    );
  }

  Future<void> runFailureOperation(AppFailure failure) async {
    await executeOperation(
      OperationConfig(operation: () async => Result.failure(failure)),
    );
  }

  Future<void> runFailureOperationWithCustomError(
    AppFailure failure,
    ErrorState customError,
  ) async {
    await executeOperation(
      OperationConfig(
        operation: () async => Result.failure(failure),
        errorStateBuilder: (f) => customError,
      ),
    );
  }

  Future<void> runNoneOperation() async {
    await executeOperation(
      OperationConfig(operation: () async => const Result.none()),
    );
  }

  Future<void> runCancelOperation() async {
    await executeOperation(
      OperationConfig(operation: () async => const Result.cancel()),
    );
  }

  Future<void> runConvertedOperation(int value) async {
    await executeOperation(
      OperationConfig(operation: () async => Result.success(value)),
      convert: (data) => 'value=$data',
    );
  }

  void exposeUpdateState({
    ViewState? state,
    String? data,
    bool retainOldData = true,
  }) {
    updateState(state: state, data: data, retainOldData: retainOldData);
  }
}

/// Provider that performs delayed async work inside [initialize].
class AsyncInitProvider extends BaseProvider<String> {
  AsyncInitProvider({
    this.delay = const Duration(milliseconds: 40),
    this.seedData = 'restored',
    this.throwOnInit = false,
  }) : super();

  final Duration delay;
  final String seedData;
  final bool throwOnInit;

  var initializeStarted = false;
  var initializeCompleted = false;
  var initializeCallCount = 0;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    initializeStarted = true;
    await super.initialize();

    if (throwOnInit) {
      throw StateError('init failed');
    }

    await Future<void>.delayed(delay);
    updateState(state: const ViewState.success(), data: seedData);
    initializeCompleted = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseProvider lifecycle (initialize / ensureInitialized)', () {
    test(
      'ensureInitialized resolves only after async initialize completes',
      () async {
        final provider = AsyncInitProvider();

        expect(provider.initializeCompleted, isFalse);
        expect(provider.data, isNull);

        await provider.ensureInitialized();

        expect(provider.initializeStarted, isTrue);
        expect(provider.initializeCompleted, isTrue);
        expect(provider.isSuccess, isTrue);
        expect(provider.data, equals('restored'));
      },
    );

    test(
      'ensureInitialized is idempotent after initialization finishes',
      () async {
        final provider = AsyncInitProvider(
          delay: const Duration(milliseconds: 10),
        );

        await provider.ensureInitialized();
        await provider.ensureInitialized();
        await provider.ensureInitialized();

        expect(provider.initializeCallCount, equals(1));
        expect(provider.data, equals('restored'));
      },
    );

    test(
      'concurrent ensureInitialized callers wait for the same initialize',
      () async {
        final provider = AsyncInitProvider(
          delay: const Duration(milliseconds: 50),
        );

        await Future.wait([
          provider.ensureInitialized(),
          provider.ensureInitialized(),
          provider.ensureInitialized(),
        ]);

        expect(provider.initializeCallCount, equals(1));
        expect(provider.initializeCompleted, isTrue);
        expect(provider.data, equals('restored'));
      },
    );

    test(
      'ensureInitialized still completes when initialize throws and reports FlutterError',
      () async {
        FlutterErrorDetails? reported;
        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          reported = details;
        };

        try {
          final provider = AsyncInitProvider(throwOnInit: true);

          await provider.ensureInitialized();

          expect(provider.initializeStarted, isTrue);
          expect(provider.initializeCompleted, isFalse);
          expect(provider.data, isNull);
          expect(reported, isNotNull);
          expect(reported!.exception, isA<StateError>());
          expect(reported!.exception.toString(), contains('init failed'));
          expect(reported!.library, equals('provider_state_management'));
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );

    test(
      'default initialize (no override) still lets ensureInitialized complete',
      () async {
        final provider = TestProvider();

        await provider.ensureInitialized();

        expect(provider.viewState.state, equals(const ViewState.initial()));
      },
    );

    test('dispose completes pending ensureInitialized', () async {
      final provider = AsyncInitProvider(
        delay: const Duration(milliseconds: 200),
      );

      final pending = provider.ensureInitialized();
      provider.dispose();

      await pending;
      expect(provider.isDisposed, isTrue);
    });
  });

  group('BaseProvider executeOperation', () {
    late TestProvider provider;

    setUp(() async {
      provider = TestProvider();
      await provider.ensureInitialized();
    });

    tearDown(() {
      if (!provider.isDisposed) {
        provider.dispose();
      }
    });

    test('starts in initial state', () {
      expect(provider.viewState.state, equals(const ViewState.initial()));
      expect(provider.data, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.isSuccess, isFalse);
      expect(provider.isError, isFalse);
    });

    test('transitions loading → success on successful operation', () async {
      final states = <ViewState>[];
      final sub = provider.listen((stateModel) {
        states.add(stateModel.state);
      });

      await provider.runSuccessOperation('Test Success Data');

      expect(provider.isSuccess, isTrue);
      expect(provider.data, equals('Test Success Data'));
      expect(
        states,
        containsAllInOrder([
          const ViewState.loading(),
          const ViewState.success(),
        ]),
      );

      await sub.cancel();
    });

    test('showLoading: false skips loading when data is null', () async {
      final states = <ViewState>[];
      final sub = provider.listen((stateModel) {
        states.add(stateModel.state);
      });

      await provider.runSuccessOperation('quiet', showLoading: false);

      expect(provider.isSuccess, isTrue);
      expect(provider.data, equals('quiet'));
      expect(states, equals([const ViewState.success()]));

      await sub.cancel();
    });

    test('does not show loading when data already exists', () async {
      await provider.runSuccessOperation('first');
      final states = <ViewState>[];
      final sub = provider.listen((stateModel) {
        states.add(stateModel.state);
      });

      await provider.runSuccessOperation('second');

      expect(provider.data, equals('second'));
      expect(states, equals([const ViewState.success()]));
      expect(states, isNot(contains(const ViewState.loading())));

      await sub.cancel();
    });

    test('transitions loading → error on failed operation', () async {
      final states = <ViewState>[];
      final sub = provider.listen((stateModel) {
        states.add(stateModel.state);
      });

      const failure = ServerFailure(message: 'Request Timeout', code: 504);
      await provider.runFailureOperation(failure);

      expect(provider.isError, isTrue);
      expect(provider.viewState.message, equals('Request Timeout'));
      expect(states.length, equals(2));
      expect(states[0], equals(const ViewState.loading()));
      expect(states[1].isError, isTrue);

      await sub.cancel();
    });

    test('maps failure to custom ErrorState via errorStateBuilder', () async {
      const failure = ServerFailure(message: 'Internal Error', code: 500);
      const customError = CustomAppErrorState(
        errorCode: 'ERR_500',
        description: 'Server Internal Error',
      );

      await provider.runFailureOperationWithCustomError(failure, customError);

      expect(provider.isError, isTrue);
      expect(provider.viewState.message, equals('Internal Error'));

      provider.viewState.state.whenOrNull(
        error: (error) {
          expect(error, isA<CustomAppErrorState>());
          final typedError = error as CustomAppErrorState;
          expect(typedError.errorCode, equals('ERR_500'));
        },
      );
    });

    test('Result.success(null) retains previous data by default', () async {
      await provider.runSuccessOperation('user');
      expect(provider.data, equals('user'));

      await provider.runVoidSuccessOperation();

      expect(provider.isSuccess, isTrue);
      expect(provider.data, equals('user'));
    });

    test(
      'onSuccess can clear retained data with retainOldData: false',
      () async {
        await provider.runSuccessOperation('user');
        await provider.runVoidSuccessAndClear();

        expect(provider.isSuccess, isTrue);
        expect(provider.data, isNull);
      },
    );

    test('Result.none does not change state', () async {
      await provider.runSuccessOperation('keep');
      final before = provider.viewState;

      await provider.runNoneOperation();

      expect(provider.viewState, equals(before));
      expect(provider.data, equals('keep'));
    });

    test('Result.cancel does not change state', () async {
      await provider.runSuccessOperation('keep');
      final before = provider.viewState;

      await provider.runCancelOperation();

      expect(provider.viewState, equals(before));
      expect(provider.data, equals('keep'));
    });

    test('convert maps Result type to provider state type', () async {
      await provider.runConvertedOperation(42);

      expect(provider.isSuccess, isTrue);
      expect(provider.data, equals('value=42'));
    });

    test('updateState can clear data with retainOldData: false', () {
      provider.exposeUpdateState(
        state: const ViewState.success(),
        data: 'temp',
      );
      expect(provider.data, equals('temp'));

      provider.exposeUpdateState(
        state: const ViewState.success(),
        data: null,
        retainOldData: false,
      );
      expect(provider.data, isNull);
    });

    test('operations after dispose are no-ops', () async {
      await provider.runSuccessOperation('alive');
      provider.dispose();

      await provider.runSuccessOperation('ignored');

      expect(provider.isDisposed, isTrue);
      expect(provider.data, equals('alive'));
    });
  });
}
