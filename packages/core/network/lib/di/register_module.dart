import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import '../src/api_client.dart';

@module
abstract class RegisterModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();
}
