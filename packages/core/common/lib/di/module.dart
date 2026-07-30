import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

/// Global service locator instance
final GetIt getIt = GetIt.instance;

T? getItOrNull<T extends Object>({
  dynamic param1,
  dynamic param2,
  String? instanceName,
  Type? type,
}) {
  return getIt.maybeGet<T>(
    param1: param1,
    param2: param2,
    instanceName: instanceName,
    type: type,
  );
}

Iterable<T> getAll<T extends Object>({
  dynamic param1,
  dynamic param2,
  bool fromAllScopes = false,
  String? onlyInScope,
}) {
  return getIt.getAll<T>(
    param1: param1,
    param2: param2,
    fromAllScopes: fromAllScopes,
    onlyInScope: onlyInScope,
  );
}

/// Like [getAll], but returns an empty iterable when [T] is not registered
/// (instead of throwing). Use for optional multi-instance contributions
/// such as dashboard tabs or feature routes.
Iterable<T> getAllOrEmpty<T extends Object>({
  dynamic param1,
  dynamic param2,
  bool fromAllScopes = false,
  String? onlyInScope,
}) {
  if (!getIt.isRegistered<T>()) {
    return const [];
  }
  return getIt.getAll<T>(
    param1: param1,
    param2: param2,
    fromAllScopes: fromAllScopes,
    onlyInScope: onlyInScope,
  );
}
