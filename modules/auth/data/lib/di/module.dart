import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../src/data_sources/remote/auth_remote_data_source.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDataDiModule {
  /// Builds this module's Retrofit client from the shared [Dio].
  ///
  /// `Dio` comes from `core_network`'s own module, already carrying the auth,
  /// refresh, retry and logging interceptors — so the data source inherits
  /// the whole chain without knowing it exists.
  ///
  /// Constructing it here rather than inside the repository keeps the
  /// dependency visible to the container, which is what lets a test pass a
  /// fake in.
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
      AuthRemoteDataSource(dio);
}
