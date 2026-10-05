import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

import '../extensions/l10n_splash_extension.dart';
import '../utils/splash_ui_constants.dart';

/// SAMPLE — the screen behind `IAppSplashScreen`.
///
/// `MainScope` shows this before the router exists, so it must not read
/// `GoRouter` or any route-scoped controller. That constraint is the whole
/// lesson; everything else here is one screen's taste and yours to replace.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The default text colour is for the page; on the gradient every stop
    // takes the palette's on-colour (4.5:1 in both themes).
    final onGradient = context.colors.textInverse;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.liquidOnboarding(context),
        ),
        // Scrolls when the content outgrows the window (a split-screen or
        // landscape window, large text) instead of overflowing, and stays
        // centred when it fits.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlutterLogo(size: context.r(SplashUiConstants.LOGO_SIZE)),
                    SizedBox(height: AppSpacing.lgH(context)),
                    Text(
                      context.l10nSplash.appName,
                      style: AppTextStyles.headlineLargeStyle(
                        context,
                      ).copyWith(color: onGradient),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppSpacing.smH(context)),
                    Text(
                      context.l10nSplash.tagline,
                      style: AppTextStyles.bodyMediumStyle(
                        context,
                      ).copyWith(color: onGradient),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppSpacing.xlH(context)),
                    CircularProgressIndicator(color: onGradient),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
