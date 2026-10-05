import 'dart:async';

import 'package:bloc_state_management/bloc_state_management.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_home/feature_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAuthStatusStream implements ISessionStatusStream {
  _FakeAuthStatusStream({this.currentUser});

  final controller = StreamController<SessionPrincipal?>.broadcast();

  /// Closes [controller]; each test registers it with `addTearDown`.
  Future<void> close() => controller.close();

  @override
  SessionPrincipal? currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => controller.stream;
}

/// A [HomeProfileBloc] a test can push a state into, to reach the states the
/// stream-mapping bloc itself never emits (it only ever settles on success).
class _ScriptedBloc extends HomeProfileBloc {
  _ScriptedBloc() : super(null);

  void show(BlocViewState<SessionPrincipal?> state) => emit(state);
}

class _LightThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

const _ada = SessionPrincipal(id: '1', displayName: 'Ada');
const _anonymous = SessionPrincipal(id: '2');

void main() {
  _FakeAuthStatusStream newAuth({SessionPrincipal? currentUser}) {
    final auth = _FakeAuthStatusStream(currentUser: currentUser);
    addTearDown(auth.close);
    return auth;
  }

  Future<void> pumpHome(WidgetTester tester, HomeProfileBloc bloc) async {
    addTearDown(bloc.close);
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureHomeLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: FeatureHomeLocalizations.supportedLocales,
            home: BlocProvider<HomeProfileBloc>.value(
              value: bloc,
              child: const HomePage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FeatureHomeLocalizations l10nOf(WidgetTester tester) =>
      FeatureHomeLocalizations.of(tester.element(find.byType(HomePage)))!;

  testWidgets('with no session the page says the user is logged out', (
    tester,
  ) async {
    await pumpHome(tester, HomeProfileBloc(null));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.userLoggedOut), findsOneWidget);
    expect(find.text(l10n.userLoggedIn), findsNothing);
  });

  testWidgets('scrolls instead of overflowing on a short window with 2x '
      'text', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpHome(tester, HomeProfileBloc(newAuth(currentUser: _ada)));

    expect(tester.takeException(), isNull);
    final l10n = l10nOf(tester);
    await tester.ensureVisible(find.text(l10n.refreshProfile));
    expect(find.text(l10n.refreshProfile), findsOneWidget);
  });

  testWidgets('a signed-in user is greeted by display name', (tester) async {
    await pumpHome(
      tester,
      HomeProfileBloc(newAuth(currentUser: _ada)),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.userLoggedIn), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text(l10n.userLoggedOut), findsNothing);
  });

  testWidgets('a signed-in user without a display name shows no name line', (
    tester,
  ) async {
    await pumpHome(
      tester,
      HomeProfileBloc(newAuth(currentUser: _anonymous)),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.userLoggedIn), findsOneWidget);
    // Home title, status and the refresh button — and no name.
    expect(find.byType(Text), findsNWidgets(3));
  });

  testWidgets('the page follows a sign-in and a sign-out as they happen', (
    tester,
  ) async {
    final auth = newAuth();
    await pumpHome(tester, HomeProfileBloc(auth));
    final l10n = l10nOf(tester);
    expect(find.text(l10n.userLoggedOut), findsOneWidget);

    auth.controller.add(_ada);
    await tester.pumpAndSettle();
    expect(find.text(l10n.userLoggedIn), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);

    auth.controller.add(null);
    await tester.pumpAndSettle();
    expect(find.text(l10n.userLoggedOut), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
  });

  testWidgets('refresh re-reads a user the stream never announced', (
    tester,
  ) async {
    final auth = newAuth();
    await pumpHome(tester, HomeProfileBloc(auth));
    final l10n = l10nOf(tester);

    // A broadcast stream does not replay: this change is invisible to the
    // page until it asks again.
    auth.currentUser = _ada;
    await tester.pumpAndSettle();
    expect(find.text(l10n.userLoggedOut), findsOneWidget);

    await tester.tap(find.text(l10n.refreshProfile));
    await tester.pumpAndSettle();

    expect(find.text(l10n.userLoggedIn), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('while loading, only a progress indicator shows', (tester) async {
    final bloc = _ScriptedBloc();
    await pumpHome(tester, bloc);

    bloc.show(const BlocViewState.loading());
    // One pump delivers the state to the BlocBuilder, the next rebuilds it.
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(l10nOf(tester).refreshProfile), findsNothing);
  });
}
