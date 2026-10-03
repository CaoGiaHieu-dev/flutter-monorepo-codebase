import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:material_ui/material_ui.dart';

/// Replaces a blank window: what a person sees when the app stops itself
/// before it can show anything.
///
/// Runs a minimal app that needs no dependency injection, no router and no
/// theme provider — none of them exist yet when the boot stops. [detailed]
/// chooses the text: the full diagnostics (every problem, with what to do) for
/// a developer or tester, or only a generic message for a production release,
/// where the user cannot act on them.
void runBootError(List<ProfileProblem> problems, {required bool detailed}) {
  runApp(BootErrorApp(problems: problems, detailed: detailed));
}

/// The widget [runBootError] runs, public so a test can pump it.
class BootErrorApp extends StatelessWidget {
  const BootErrorApp({
    super.key,
    required this.problems,
    required this.detailed,
  });

  /// What stopped the boot.
  final List<ProfileProblem> problems;

  /// Whether to show [problems] in full, rather than a generic message.
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          ResponsiveInit(child: child ?? const SizedBox.shrink()),
      home: _BootErrorScreen(problems: problems, detailed: detailed),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.problems, required this.detailed});

  final List<ProfileProblem> problems;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = SizedBox(height: AppSpacing.lgH(context));

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.xl(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                size: context.w(AppSpacing.rawXxxl),
              ),
              gap,
              Text(
                context.l10n.somethingWentWrong,
                style: theme.textTheme.headlineSmall,
              ),
              gap,
              if (detailed)
                for (final problem in problems) ...[
                  // Developer diagnostics: composed from the app's manifest
                  // and profile, English by design — like a stack trace.
                  SelectableText(
                    '[${problem.code}] ${problem.description}\n'
                    'Action: ${problem.action}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  gap,
                ]
              else
                Text(context.l10n.tryAgain, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
