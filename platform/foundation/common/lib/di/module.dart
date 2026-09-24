import 'package:injectable/injectable.dart';

/// Re-exported so `package:core_common/di/module.dart` keeps resolving
/// `getIt`, `getItOrNull`, `getAll` and `getAllOrEmpty`. They now live in
/// `platform_kernel`, which declares no Flutter dependency.
export 'package:platform_kernel/platform_kernel.dart'
    show getIt, getItOrNull, getAll, getAllOrEmpty;

@InjectableInit.microPackage()
void initMicroPackage() {}
