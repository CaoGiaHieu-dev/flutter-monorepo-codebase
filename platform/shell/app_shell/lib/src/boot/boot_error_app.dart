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
///
/// [onRetry], when given, adds a retry button: the screen is for a failure
/// that may not come back (a storage that was locked, a connection that
/// dropped), as opposed to a declaration that stays wrong until the app is
/// rebuilt.
void runBootError(
  List<ProfileProblem> problems, {
  required bool detailed,
  Future<void> Function()? onRetry,
}) {
  runApp(
    BootErrorApp(problems: problems, detailed: detailed, onRetry: onRetry),
  );
}

/// What [runBootError] shows when the boot *threw* — `configureDependencies`,
/// an initializer or an app hook — rather than found a wrong declaration:
/// without it the user stays on a splash that never ends, or a blank window.
///
/// [error] is shown only where [detailed] (a developer or tester build); a
/// production release shows the generic message. [onRetry] starts the boot
/// over.
void runBootFailure(
  Object error, {
  required bool detailed,
  required Future<void> Function() onRetry,
}) {
  runBootError(
    [
      ProfileProblem(
        code: bootFailureCode,
        description: 'The app failed while starting: $error',
        action:
            'Fix the cause and retry. The error was also reported to the '
            'app\'s error hook and IErrorReporter.',
      ),
    ],
    detailed: detailed,
    onRetry: onRetry,
  );
}

/// The problem code of a boot that threw (`B01`), as opposed to `P01`–`P05`
/// (profile) and `C01`–`C10` (composition) which are declarations.
const String bootFailureCode = 'B01';

/// The widget [runBootError] runs, public so a test can pump it.
class BootErrorApp extends StatelessWidget {
  const BootErrorApp({
    super.key,
    required this.problems,
    required this.detailed,
    this.onRetry,
  });

  /// What stopped the boot.
  final List<ProfileProblem> problems;

  /// Whether to show [problems] in full, rather than a generic message.
  final bool detailed;

  /// Starts the boot over. With it the screen has a retry button; without it
  /// (a wrong declaration, which retrying cannot fix) there is none.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          ResponsiveInit(child: child ?? const SizedBox.shrink()),
      home: _BootErrorScreen(
        problems: problems,
        detailed: detailed,
        onRetry: onRetry,
      ),
    );
  }
}

class _BootErrorScreen extends StatefulWidget {
  const _BootErrorScreen({
    required this.problems,
    required this.detailed,
    required this.onRetry,
  });

  final List<ProfileProblem> problems;
  final bool detailed;
  final Future<void> Function()? onRetry;

  @override
  State<_BootErrorScreen> createState() => _BootErrorScreenState();
}

class _BootErrorScreenState extends State<_BootErrorScreen> {
  /// A second tap while the boot restarts would start a second boot.
  bool _retrying = false;

  Future<void> _retry() async {
    final onRetry = widget.onRetry;
    if (onRetry == null || _retrying) return;
    setState(() => _retrying = true);
    await onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final problems = widget.problems;
    final detailed = widget.detailed;
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
              if (widget.onRetry != null) ...[
                if (!detailed) gap,
                FilledButton(
                  onPressed: _retrying ? null : _retry,
                  child: Text(context.l10n.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
