import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../src/provider/auth_provider.dart';

/// Mounts [AuthProvider] above the router so this feature's pages can read it
/// from the widget tree (`context.read<AuthProvider>()`, `Consumer<…>`).
///
/// Registering it here rather than in the app shell is what keeps the shell
/// free of a `feature_auth` import: remove this package and the shell simply
/// finds no wrapper to apply.
@LazySingleton(as: IAppTreeWrapper)
class AuthTreeWrapper implements IAppTreeWrapper {
  @override
  int get order => 0;

  @override
  Widget wrap(BuildContext context, Widget child) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: getIt<AuthProvider>(),
      child: child,
    );
  }
}
