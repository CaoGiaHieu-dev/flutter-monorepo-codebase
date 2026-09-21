import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/extensions.dart';

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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.liquidOnboarding(context),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlutterLogo(size: context.w(64)),
              SizedBox(height: AppSpacing.lgH(context)),
              Text(
                context.l10nSplash.appName,
                style: AppTextStyles.headlineLargeStyle(context),
              ),
              SizedBox(height: AppSpacing.smH(context)),
              Text(
                context.l10nSplash.tagline,
                style: AppTextStyles.bodyMediumStyle(context),
              ),
              SizedBox(height: AppSpacing.xlH(context)),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
