import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class UndefineRouteWidget extends StatelessWidget {
  const UndefineRouteWidget({super.key, required this.state});
  final GoRouterState state;

  String get _fallbackLocation {
    final entry = getItOrNull<IAppEntryLocation>()?.path;
    if (entry != null) return entry;
    final tabs = getAllOrEmpty<IDashboardTabModule>().toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (tabs.isNotEmpty) return tabs.first.path;
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(title: Text('${state.uri}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(context.l10n.page_not_found),
            SizedBox(height: context.h(16)),
            ElevatedButton(
              onPressed: () {
                if (canPop) {
                  context.pop();
                } else {
                  context.go(_fallbackLocation);
                }
              },
              child: Text(
                canPop ? context.l10n.go_back : context.l10n.go_to_home,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
