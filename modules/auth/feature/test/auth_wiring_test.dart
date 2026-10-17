import 'package:auth_api/auth_api.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider_state_management/provider_state_management.dart';

import 'auth_fakes.dart';

/// The contributions other code reaches through DI contracts, not through
/// imports: the tree wrapper, the `auth_api` action handler, the sign-in path.
void main() {
  late FakeAuthRepository repository;
  late AuthProvider auth;

  setUp(() {
    repository = FakeAuthRepository();
    auth = AuthProvider(
      LoginUseCase(repository),
      repository,
      AuthStatusStreamImpl(),
    );
  });

  tearDown(() => auth.dispose());

  testWidgets('AuthTreeWrapper puts the app-wide AuthProvider above the app', (
    tester,
  ) async {
    late AuthProvider found;
    await tester.pumpWidget(
      Builder(
        builder: (context) => AuthTreeWrapper(auth).wrap(
          context,
          Builder(
            builder: (inner) {
              found = inner.read<AuthProvider>();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(found, same(auth));
  });

  testWidgets('IAuthActionHandler.logout ends the session via the provider', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final IAuthActionHandler handler = AuthActionHandlerImpl();
    await handler.logout(context);

    expect(repository.logouts, 1);
  });

  test('the shell is sent to the login route when signed out', () {
    expect(AuthSignInLocation().path, AuthPath.LOGIN);
    expect(const LoginRoute().location, AuthPath.LOGIN);
  });
}
