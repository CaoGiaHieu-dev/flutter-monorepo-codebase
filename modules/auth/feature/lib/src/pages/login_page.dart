import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

import '../extensions/l10n_auth_extension.dart';
import '../provider/auth_error_state.dart';
import '../provider/auth_provider.dart';

/// SAMPLE — the one screen of the auth module: a translated login form on a
/// global Provider controller.
///
/// - **No `ChangeNotifierProvider` here**: `AuthProvider` is mounted once by
///   `AuthTreeWrapper`; wrapping again would build a second instance (RULE-21).
/// - **`ProviderStateListener`** runs a side effect of a failed sign-in: a
///   rejected password is cleared. The failure's message is not shown here: the
///   shell announces every session failure as a translated toast.
/// - **`Selector`** rebuilds only the button when `isLoading` changes.
/// - **No navigation on success**: the shell listens to the session and routes.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? context.l10nAuth.fieldRequired
      : null;

  /// The email is sent trimmed (a keyboard's autocomplete leaves a trailing
  /// space); the password exactly as typed.
  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthProvider>().login(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProviderStateListener<AuthProvider, UserEntity>(
      onError: (context, error, _) {
        if (error == const AuthErrorState.invalidCredentials()) {
          _passwordController.clear();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.xl(context)),
            child: AdaptiveContent(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Text(
                      context.l10nAuth.welcomeBack,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineLargeStyle(context),
                    ),
                    SizedBox(height: AppSpacing.xxlH(context)),
                    CustomInputField(
                      controller: _emailController,
                      hintText: context.l10nAuth.enterYourEmail,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _required,
                    ),
                    SizedBox(height: AppSpacing.lgH(context)),
                    CustomInputField(
                      controller: _passwordController,
                      hintText: context.l10nAuth.enterYourPassword,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: _required,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    SizedBox(height: AppSpacing.xlH(context)),
                    Selector<AuthProvider, bool>(
                      selector: (_, auth) => auth.isLoading,
                      builder: (context, isLoading, _) =>
                          CustomButton.rectangle(
                            disable: isLoading,
                            onPressed: _submit,
                            child: isLoading
                                ? CircularProgressIndicator(
                                    semanticsLabel: context.l10n.loading,
                                  )
                                : Text(context.l10nAuth.signIn),
                          ),
                    ),
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
