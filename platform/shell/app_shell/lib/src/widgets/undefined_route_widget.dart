import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../navigation/app_router.dart';

class UndefineRouteWidget extends StatelessWidget {
  const UndefineRouteWidget({super.key, required this.state});
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
            SizedBox(height: context.h(16)),
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
