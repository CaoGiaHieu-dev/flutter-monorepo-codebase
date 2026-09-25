import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../src/api_client.dart';

/// Registers the app's default [Dio], built by [ApiClient] with the auth,
/// refresh, retry and logging interceptors.
@module
abstract class NetworkModule {
  @lazySingleton
  Dio dio(ApiClient apiClient) => apiClient.createClient();
}
