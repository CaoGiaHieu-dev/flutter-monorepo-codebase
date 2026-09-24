import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class CoreStorageDiModule {
  @preResolve
  Future<SharedPreferences> getSharedPreferences() async {
    return SharedPreferences.getInstance();
  }
}
