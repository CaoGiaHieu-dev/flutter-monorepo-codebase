import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../extensions/l10n_auth_extension.dart';
import '../provider/auth_error_state.dart';
import '../provider/auth_provider.dart';
import '../widgets/auth_form_widget.dart';
import '../widgets/auth_header_widget.dart';

/// SAMPLE — the one screen of the auth reference module.
///
/// What it demonstrates, and why each line is here:
///
/// - **No `ChangeNotifierProvider` in this file.** `AuthProvider` is mounted
///   once by `AuthTreeWrapper` (an `IAppTreeWrapper` contributed through DI).
///   Wrapping again here would build a second instance and desynchronise state
///   — see RULE-21.
/// - **`ProviderStateListener`** for a side effect of a failed sign-in: a
///   rejected password is cleared, so the next attempt starts from an empty
///   field. It fires once per failed attempt, even two identical ones in a
///   row. The failure's *message* is not shown here: the app shell already
///   announces every session failure as a translated toast (it listens to
///   `ISessionState.sessionFailures`), and a second toast would repeat it.
/// - **`Consumer<AuthProvider>`** rebuilds only the form on `isLoading`.
/// - **No navigation on success.** `AuthProvider` publishes the session change,
///   the app shell listens and routes. A page that navigates itself would
///   double-navigate the moment the shell does its job.
/// - **`AdaptiveContent`** caps the form's width on a tablet or desktop
///   window; on a phone it changes nothing.
///
/// Replace it with a real screen, or delete the package — nothing in the
/// framework references it.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLoginPressed() => context.read<AuthProvider>().login(
    _emailController.text,
    _passwordController.text,
  );

  void _onLoginFailed(BuildContext context, ErrorState? error, String? _) {
    if (error == const AuthErrorState.invalidCredentials()) {
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProviderStateListener<AuthProvider, UserEntity>(
      onError: _onLoginFailed,
      child: Scaffold(
        backgroundColor: context.colors.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.xl(context)),
            // On a tablet or desktop window the form keeps a readable width
            // instead of stretching across the screen.
            child: AdaptiveContent(
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  return Column(
                    children: [
                      SizedBox(height: AppSpacing.xxlH(context)),
                      AuthHeaderWidget(
                        title: context.l10nAuth.welcomeBack,
                        subtitle: context.l10nAuth.signInSubtitle,
                      ),
                      SizedBox(height: AppSpacing.xxlH(context)),
                      AuthFormWidget(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        submitButtonText: context.l10nAuth.signIn,
                        isLoading: authProvider.isLoading,
                        onSubmit: _onLoginPressed,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
