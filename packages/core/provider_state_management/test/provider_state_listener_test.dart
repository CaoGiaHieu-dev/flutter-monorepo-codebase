import 'package:domain_core/domain_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

// ── Test Provider ──────────────────────────────────────────────────────────

class TestProvider extends BaseProvider<String> {
  TestProvider() : super();

  Future<void> runSuccessOperation(String data) async {
    await executeOperation(
      OperationConfig(operation: () async => Result.success(data)),
    );
  }

  Future<void> runFailureOperation(AppFailure failure) async {
    await executeOperation(
      OperationConfig(operation: () async => Result.failure(failure)),
    );
  }

  Future<void> runFailureWithCustomError(
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
}

// ── Test App helper ────────────────────────────────────────────────────────

Widget _buildTestApp({required TestProvider provider, required Widget child}) {
  return ChangeNotifierProvider<TestProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProviderStateListener', () {
    late TestProvider provider;

    setUp(() {
      provider = TestProvider();
    });

    testWidgets('should call onLoading when state transitions to loading', (
      tester,
    ) async {
      var loadingCalled = false;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onLoading: (context) {
              loadingCalled = true;
            },
            child: const Text('child'),
          ),
        ),
      );

      // Trigger operation (will go to loading first)
      provider.runSuccessOperation('data');
      await tester.pump();

      expect(loadingCalled, isTrue);
    });

    testWidgets('should call onSuccess when state transitions to success', (
      tester,
    ) async {
      String? receivedData;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onSuccess: (context, data) {
              receivedData = data;
            },
            child: const Text('child'),
          ),
        ),
      );

      await provider.runSuccessOperation('hello');
      await tester.pump();

      expect(receivedData, equals('hello'));
    });

    testWidgets('should call onError when state transitions to error', (
      tester,
    ) async {
      String? receivedMessage;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onError: (context, error, message) {
              receivedMessage = message;
            },
            child: const Text('child'),
          ),
        ),
      );

      const failure = ServerFailure(message: 'Server down', code: 500);
      await provider.runFailureOperation(failure);
      await tester.pump();

      expect(receivedMessage, equals('Server down'));
    });

    testWidgets('should pass custom ErrorState to onError callback', (
      tester,
    ) async {
      ErrorState? receivedError;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onError: (context, error, message) {
              receivedError = error;
            },
            child: const Text('child'),
          ),
        ),
      );

      const failure = ServerFailure(message: 'Unauthorized', code: 401);
      const customError = ErrorState.raw({'type': 'auth', 'code': 401});

      await provider.runFailureWithCustomError(failure, customError);
      await tester.pump();

      expect(receivedError, isNotNull);
    });

    testWidgets('should call onStateChanged on every state transition', (
      tester,
    ) async {
      final stateChanges = <ViewState>[];

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onStateChanged: (context, state) {
              stateChanges.add(state.state);
            },
            child: const Text('child'),
          ),
        ),
      );

      await provider.runSuccessOperation('data');
      await tester.pump();

      // Should have captured loading → success
      expect(stateChanges.length, equals(2));
      expect(stateChanges[0].isLoading, isTrue);
      expect(stateChanges[1].isSuccess, isTrue);
    });

    testWidgets('should respect listenWhen filter', (tester) async {
      var errorCalled = false;
      var loadingCalled = false;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            // Only listen to error states
            listenWhen: (previous, current) => current.state.isError,
            onLoading: (context) {
              loadingCalled = true;
            },
            onError: (context, error, message) {
              errorCalled = true;
            },
            child: const Text('child'),
          ),
        ),
      );

      const failure = ServerFailure(message: 'Fail', code: 500);
      await provider.runFailureOperation(failure);
      await tester.pump();

      // Loading callback should NOT be called (filtered out)
      expect(loadingCalled, isFalse);
      // Error callback SHOULD be called
      expect(errorCalled, isTrue);
    });

    testWidgets('should render child widget unchanged', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: const ProviderStateListener<TestProvider, String>(
            child: Text('my child widget'),
          ),
        ),
      );

      expect(find.text('my child widget'), findsOneWidget);
    });

    testWidgets('should cancel subscription on dispose', (tester) async {
      var callCount = 0;

      await tester.pumpWidget(
        _buildTestApp(
          provider: provider,
          child: ProviderStateListener<TestProvider, String>(
            onSuccess: (context, data) {
              callCount++;
            },
            child: const Text('child'),
          ),
        ),
      );

      // Now remove the listener widget from the tree
      await tester.pumpWidget(
        _buildTestApp(provider: provider, child: const Text('no listener')),
      );

      // Trigger success after listener is disposed
      await provider.runSuccessOperation('late data');
      await tester.pump();

      // Callback should NOT have been called
      expect(callCount, equals(0));
    });
  });

  group('MultiProviderStateListener', () {
    testWidgets('should render child and allow nested listeners', (
      tester,
    ) async {
      final provider = TestProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<TestProvider>.value(
          value: provider,
          child: MaterialApp(
            home: MultiProviderStateListener(
              listeners: [
                ProviderStateListenerEntry<TestProvider, String>(
                  onError: (context, error, message) {
                    // noop for structural test
                  },
                ),
              ],
              child: const Text('multi child'),
            ),
          ),
        ),
      );

      expect(find.text('multi child'), findsOneWidget);
    });
  });
}
