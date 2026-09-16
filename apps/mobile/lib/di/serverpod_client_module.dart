import 'package:app_client/app_client.dart';
import 'package:core_common/core_common.dart';
import 'package:injectable/injectable.dart';

/// Dependency injection module for Serverpod RPC client.
@module
abstract class ServerpodClientModule {
  /// Provides singleton instance of [AppServerClient] for mobile app.
  @lazySingleton
  AppServerClient provideServerpodClient() {
    final baseUrl = EnvConstants.BASE_URL.isNotEmpty
        ? EnvConstants.BASE_URL
        : 'http://localhost:8080/';
    return AppServerClient(baseUrl);
  }
}
