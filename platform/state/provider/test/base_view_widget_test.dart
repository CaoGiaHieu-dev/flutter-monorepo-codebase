import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide ErrorWidgetBuilder;
import 'package:provider_state_management/provider_state_management.dart';

class _Names extends BaseProvider<String> {
  _Names() : super();

  void emit({ViewState? state, String? data, String? message}) =>
      updateState(state: state, data: data, message: message);
}

/// `BaseViewWidget` picks one widget per view state: the loading widget for
/// `initial` and `loading`, the data builder for `success`, the error builder
/// (or the data builder) for `error`, and the empty widget when there is no
/// data to build from.
void main() {
  late _Names provider;

  setUp(() => provider = _Names());
  tearDown(() => provider.dispose());

  Future<void> pump(
    WidgetTester tester, {
    InitialWidgetBuilder? initialWidget,
    LoadingWidgetBuilder? loadingWidget,
    EmptyWidgetBuilder? emptyWidget,
    ErrorWidgetBuilder<String?>? onErrorBuilder,
    Widget? child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<_Names>.value(
          value: provider,
          child: BaseViewWidget<_Names, String>(
            builder: (context, value, child) => Text('data: $value'),
            initialWidget: initialWidget,
            loadingWidget: loadingWidget,
            emptyWidget: emptyWidget,
            onErrorBuilder: onErrorBuilder,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('defaults', () {
    testWidgets('initial shows the default loading widget', (tester) async {
      await pump(tester);

      expect(find.byType(DefaultLoadingWidget), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loading shows the default loading widget', (tester) async {
      provider.emit(state: const ViewState.loading());
      await pump(tester);

      expect(find.byType(DefaultLoadingWidget), findsOneWidget);
    });

    testWidgets('success with data builds the data widget', (tester) async {
      provider.emit(state: const ViewState.success(), data: 'ada');
      await pump(tester);

      expect(find.text('data: ada'), findsOneWidget);
      expect(find.byType(DefaultLoadingWidget), findsNothing);
    });

    testWidgets('success without data shows the default empty widget', (
      tester,
    ) async {
      provider.emit(state: const ViewState.success());
      await pump(tester);

      expect(find.byType(DefaultEmptyWidget), findsOneWidget);
      expect(find.textContaining('data:'), findsNothing);
    });

    testWidgets('error without an error builder falls back to the data', (
      tester,
    ) async {
      provider.emit(state: const ViewState.error(), data: 'stale');
      await pump(tester);

      expect(find.text('data: stale'), findsOneWidget);
    });

    testWidgets('error with no data and no builder shows the empty widget', (
      tester,
    ) async {
      provider.emit(state: const ViewState.error());
      await pump(tester);

      expect(find.byType(DefaultEmptyWidget), findsOneWidget);
    });

    testWidgets('loadingMore keeps the data on screen', (tester) async {
      provider.emit(state: const ViewState.loadingMore(), data: 'page 1');
      await pump(tester);

      expect(find.text('data: page 1'), findsOneWidget);
      expect(find.byType(DefaultLoadingWidget), findsNothing);
    });
  });

  group('custom builders', () {
    testWidgets('loadingWidget replaces the default for loading', (
      tester,
    ) async {
      provider.emit(state: const ViewState.loading());
      await pump(tester, loadingWidget: (_, _) => const Text('spinner'));

      expect(find.text('spinner'), findsOneWidget);
      expect(find.byType(DefaultLoadingWidget), findsNothing);
    });

    testWidgets('initial prefers initialWidget, then loadingWidget', (
      tester,
    ) async {
      await pump(
        tester,
        initialWidget: (_, _) => const Text('start'),
        loadingWidget: (_, _) => const Text('spinner'),
      );
      expect(find.text('start'), findsOneWidget);

      await pump(tester, loadingWidget: (_, _) => const Text('spinner'));
      expect(find.text('spinner'), findsOneWidget);
    });

    testWidgets('emptyWidget replaces the default when there is no data', (
      tester,
    ) async {
      provider.emit(state: const ViewState.success());
      await pump(tester, emptyWidget: (_, _) => const Text('nothing here'));

      expect(find.text('nothing here'), findsOneWidget);
      expect(find.byType(DefaultEmptyWidget), findsNothing);
    });

    testWidgets('onErrorBuilder gets the data and the message', (tester) async {
      provider.emit(
        state: const ViewState.error(),
        data: 'stale',
        message: 'boom',
      );
      await pump(
        tester,
        onErrorBuilder: (_, data, message, _) =>
            Text('error: $message / $data'),
      );

      expect(find.text('error: boom / stale'), findsOneWidget);
    });

    testWidgets('child is passed through to the builders', (tester) async {
      provider.emit(state: const ViewState.loading());
      await pump(
        tester,
        child: const Text('static'),
        loadingWidget: (_, child) => Column(children: [?child]),
      );

      expect(find.text('static'), findsOneWidget);
    });
  });

  testWidgets('rebuilds when the provider moves from loading to success', (
    tester,
  ) async {
    provider.emit(state: const ViewState.loading());
    await pump(tester);
    expect(find.byType(DefaultLoadingWidget), findsOneWidget);

    provider.emit(state: const ViewState.success(), data: 'done');
    await tester.pump();

    expect(find.text('data: done'), findsOneWidget);
    expect(find.byType(DefaultLoadingWidget), findsNothing);
  });
}
