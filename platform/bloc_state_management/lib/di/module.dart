import 'package:injectable/injectable.dart';

@InjectableInit.microPackage(ignoreUnregisteredTypesInPackages: ['domain'])
void initMicroPackage() {}
