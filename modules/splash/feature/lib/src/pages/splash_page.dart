import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

/// SAMPLE — the screen behind `IAppSplashScreen`.
///
/// `MainScope` shows this before the router exists, so it must not read
/// `GoRouter` or any route-scoped controller. That constraint is the whole
/// lesson; everything else here is one screen's taste and yours to replace.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlutterLogo(size: context.r(64)),
            SizedBox(height: AppSpacing.xlH(context)),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
