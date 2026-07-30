import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../src/services/auth_status_stream_impl.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class AuthDiModule {
  @singleton
  IAuthStatusStream bindIAuthStatusStream(AuthStatusStreamImpl impl) => impl;
}
