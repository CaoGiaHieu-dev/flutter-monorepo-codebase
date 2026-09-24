import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider_state_management/provider_state_management.dart';

class _Feed extends ChangeNotifier with LoadMoreMixin<int> {}

Widget _app(_Feed feed, {required int itemCount, IndexedWidgetBuilder? item}) {
  return MaterialApp(
    home: ResponsiveInit(
      child: ChangeNotifierProvider<_Feed>.value(
        value: feed,
        child: Scaffold(
          body: LoadMoreListView<_Feed>(
            itemCount: itemCount,
            itemBuilder:
                item ??
                (_, index) => SizedBox(height: 40, child: Text('item $index')),
            separatorBuilder: (_, _) => const Divider(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('LoadMoreListView', () {
    testWidgets('appends the spinner after the last item', (tester) async {
      final feed = _Feed();
      addTearDown(feed.dispose);

      await tester.pumpWidget(_app(feed, itemCount: 3));
      expect(find.text('item 2'), findsOneWidget);

      feed.isLoadingMore = true;
      await tester.pump();

      // The last item keeps its slot; the spinner takes the appended one.
      expect(find.text('item 2'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('with no items, loading shows only the spinner', (
      tester,
    ) async {
      final feed = _Feed()..isLoadingMore = true;
      addTearDown(feed.dispose);
      final built = <int>[];

      await tester.pumpWidget(
        _app(
          feed,
          itemCount: 0,
          item: (_, index) {
            built.add(index);
            return Text('item $index');
          },
        ),
      );

      expect(built, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
