import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../navigation/app_router.dart';

/// The router's error page: shown for a location no module registered.
class UndefinedRouteWidget extends StatelessWidget {
  const UndefinedRouteWidget({super.key, required this.state});
  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(title: Text('${state.uri}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(context.l10n.pageNotFound),
            SizedBox(height: AppSpacing.lgH(context)),
            ElevatedButton(
              onPressed: () {
                if (canPop) {
                  context.pop();
                } else {
                  context.go(getIt<AppRouter>().fallbackLocation);
                }
              },
              child: Text(
                canPop ? context.l10n.goBack : context.l10n.goToHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
