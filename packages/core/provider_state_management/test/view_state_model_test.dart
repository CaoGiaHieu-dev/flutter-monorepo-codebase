import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

class CustomAppErrorState extends IErrorState {
  final String errorCode;
  final String description;

  const CustomAppErrorState({
    required this.errorCode,
    required this.description,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'custom_app_error',
    'errorCode': errorCode,
    'description': description,
  };

  static CustomAppErrorState fromJson(Map<String, dynamic> json) =>
      CustomAppErrorState(
        errorCode: json['errorCode'] as String,
        description: json['description'] as String,
      );

  @override
  String get $type => toString();
}

void main() {
  setUpAll(() {
    ErrorStateRegistry.register(
      'custom_app_error',
      CustomAppErrorState.fromJson,
    );
  });

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

    test('should serialize and deserialize custom ErrorState successfully', () {
      const customError = CustomAppErrorState(
        errorCode: 'ERR_401',
        description: 'Unauthorized Access',
      );

      const model = ViewStateModel<String>(
        state: ViewState.error(error: customError),
        message: 'Auth Error',
      );

      final json = model.toJson((data) => data);

      // Verification of serialized JSON structure
      expect(json['state'], isNotNull);
      expect((json['state'] as Map)['state'], equals('error'));
      expect(
        (json['state'] as Map)['error']['type'],
        equals('custom_app_error'),
      );
      expect((json['state'] as Map)['error']['errorCode'], equals('ERR_401'));

      final deserialized = ViewStateModel<String>.fromJson(
        json,
        (dataJson) => dataJson as String,
      );

      expect(deserialized.state.isError, isTrue);
      deserialized.state.whenOrNull(
        error: (error) {
          expect(error, isA<CustomAppErrorState>());
          final typedError = error as CustomAppErrorState;
          expect(typedError.errorCode, equals('ERR_401'));
          expect(typedError.description, equals('Unauthorized Access'));
        },
      );
    });

    test(
      'should fallback to RawErrorState when unregistered type is deserialized',
      () {
        final json = {
          'state': {
            'state': 'error',
            'error': {'type': 'unknown_type', 'custom_field': 'some_val'},
          },
          'message': 'Failed',
        };

        final deserialized = ViewStateModel<String>.fromJson(
          json,
          (dataJson) => dataJson as String,
        );

        expect(deserialized.state.isError, isTrue);
        deserialized.state.whenOrNull(
          error: (error) {
            expect(error, isNotNull);
            // ErrorState.raw wraps unregistered JSON data
            // $default positional arg (for unnamed ErrorState()) must be provided
            error!.maybeWhen(
              raw: (rawJson) {
                expect(rawJson['type'], equals('unknown_type'));
                expect(rawJson['custom_field'], equals('some_val'));
              },
              orElse: () => fail('Expected ErrorState.raw'),
            );
          },
        );
      },
    );
  });
}
