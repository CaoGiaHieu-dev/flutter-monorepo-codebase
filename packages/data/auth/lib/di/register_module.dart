import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

@module
abstract class RegisterModule {
  @preResolve
  Future<GoogleSignIn> get googleSignIn async {
    final instance = GoogleSignIn.instance;
    await GoogleSignIn.instance.initialize();
    return instance;
  }
}
