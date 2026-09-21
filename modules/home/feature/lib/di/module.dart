import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

/// [IAuthStatusStream] is registered by `feature_auth` (cross-feature DI hub).
@InjectableInit.microPackage()
void initMicroPackage() {}
