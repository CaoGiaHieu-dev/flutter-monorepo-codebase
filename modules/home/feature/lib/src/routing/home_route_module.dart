import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../bloc/home_profile_bloc.dart';
import '../pages/home_page.dart';
import '../utils/home_path.dart';

part 'home_route_module.g.dart';

/// SAMPLE — a tab's route is an ordinary typed route; the shell turns each
/// destination's routes into a `StatefulShellBranch`.
@TypedGoRoute<HomeRoute>(path: HomePath.HOME)
class HomeRoute extends GoRouteDataCustom with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return BlocProvider(
      // Auth is optional: an app composed without `feature_auth` registers
      // no ISessionStatusStream, and Home then shows the signed-out state.
      create: (_) => getIt<HomeProfileBloc>(
        param1: getItOrNull<ISessionStatusStream>(),
      ),
      child: const HomePage(),
    );
  }
}
