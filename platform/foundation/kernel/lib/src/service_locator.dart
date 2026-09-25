import 'package:get_it/get_it.dart';

/// Global service locator instance.
final GetIt getIt = GetIt.instance;

/// Resolves [T], or `null` when nothing is registered for it.
///
/// Use this — never bare [getIt] — whenever `T` is a contract whose only
/// implementer lives in a removable package. `arch_check` rule R8 enforces it.
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

/// Every registration of [T]. **Throws** when `T` is unregistered — prefer
/// [getAllOrEmpty] for anything a removable package contributes.
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

/// Like [getAll], but returns an empty iterable when [T] is not registered.
///
/// Use for every optional multi-instance contribution — feature routes,
/// navigation destinations, localization delegates, app-tree wrappers,
/// database migrations. A bare [getAll] there crashes the app at boot in any
/// build missing the contributor.
Iterable<T> getAllOrEmpty<T extends Object>({
  dynamic param1,
  dynamic param2,
  bool fromAllScopes = false,
  String? onlyInScope,
}) {
  if (!getIt.isRegistered<T>()) return const [];
  return getIt.getAll<T>(
    param1: param1,
    param2: param2,
    fromAllScopes: fromAllScopes,
    onlyInScope: onlyInScope,
  );
}
