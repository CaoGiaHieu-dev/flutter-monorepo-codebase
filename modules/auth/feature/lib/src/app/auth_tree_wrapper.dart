import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../provider/auth_provider.dart';

/// Mounts the global [AuthProvider] above the router, so pages read it from the
/// tree. Contributed through DI: the shell imports no feature and simply finds
/// no wrapper when this package is removed.
@LazySingleton(as: IAppTreeWrapper)
class AuthTreeWrapper implements IAppTreeWrapper {
  AuthTreeWrapper(this._authProvider);

  final AuthProvider _authProvider;

  @override
  int get order => 0;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ChangeNotifierProvider<AuthProvider>.value(
        value: _authProvider,
        child: child,
      );
}
