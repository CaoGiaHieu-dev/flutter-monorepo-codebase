import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

class CustomAppErrorState extends CustomErrorState {
  const CustomAppErrorState({
    required this.errorCode,
    required this.description,
  });

  final String errorCode;
  final String description;
}

void main() {
  group('ViewStateModel', () {
    test('initial helper methods should return correct values', () {
      const model = ViewStateModel<String>(
        state: ViewState.initial(),
        data: 'initial data',
      );

      expect(model.isInitial, isTrue);
      expect(model.isLoading, isFalse);
      expect(model.isSuccess, isFalse);
      expect(model.isError, isFalse);
      expect(model.data, equals('initial data'));
    });

    test('loading helper methods should return correct values', () {
      const model = ViewStateModel<String>(state: ViewState.loading());

      expect(model.isInitial, isFalse);
      expect(model.isLoading, isTrue);
      expect(model.isSuccess, isFalse);
      expect(model.isError, isFalse);
    });

    test('success helper methods should return correct values', () {
      const model = ViewStateModel<String>(
        state: ViewState.success(),
        data: 'success data',
      );

      expect(model.isInitial, isFalse);
      expect(model.isLoading, isFalse);
      expect(model.isSuccess, isTrue);
      expect(model.isError, isFalse);
      expect(model.data, equals('success data'));
    });

    test('error helper methods should return correct values', () {
      const model = ViewStateModel<String>(
        state: ViewState.error(),
        message: 'Something went wrong',
      );

      expect(model.isInitial, isFalse);
      expect(model.isLoading, isFalse);
      expect(model.isSuccess, isFalse);
      expect(model.isError, isTrue);
      expect(model.message, equals('Something went wrong'));
    });

    test('error state carries a feature-defined CustomErrorState', () {
      const customError = CustomAppErrorState(
        errorCode: 'ERR_401',
        description: 'Unauthorized Access',
      );

      const model = ViewStateModel<String>(
        state: ViewState.error(error: customError),
        message: 'Auth Error',
      );

      expect(model.isError, isTrue);
      final error = model.state.whenOrNull(error: (error) => error);
      expect(error, isA<ErrorState>());
      expect(error, isA<CustomAppErrorState>());
      expect((error! as CustomAppErrorState).errorCode, equals('ERR_401'));
    });
  });
}
