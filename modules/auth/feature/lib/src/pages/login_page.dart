import 'package:core_base_ui/core_base_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../extensions/extensions.dart';
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
///   — see AGENTS §3.1.
/// - **`Consumer<AuthProvider>`** rebuilds only the form on `isLoading`.
/// - **No navigation on success.** `AuthProvider` publishes the session change,
///   the app shell listens and routes. A page that navigates itself would
///   double-navigate the moment the shell does its job.
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

  void _onLoginPressed() async {
    await context.read<AuthProvider>().login(
      _emailController.text,
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.xl(context)),
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
    );
  }
}
