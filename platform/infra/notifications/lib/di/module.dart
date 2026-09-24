import 'package:injectable/injectable.dart';

@InjectableInit.microPackage(
  ignoreUnregisteredTypesInPackages: ['firebase_core'],
)
void initMicroPackage() {}
