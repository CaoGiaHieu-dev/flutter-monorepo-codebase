import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../src/data_sources/remote/auth_remote_data_source.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDataDiModule {
  /// Builds the Retrofit client from the shared [Dio] that `core_network`
  /// registers, so the data source inherits its interceptor chain. Built here,
  /// not inside the repository, so a test can pass a fake in.
  @lazySingleton
  AuthRemoteDataSource authRemoteDataSource(Dio dio) =>
      AuthRemoteDataSource(dio);
}
