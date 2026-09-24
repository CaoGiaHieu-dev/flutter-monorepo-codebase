import 'dart:async';

import 'package:core_common/core_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Counts its listeners, which [ScrollController] only exposes as protected.
class _CountingScrollController extends ScrollController {
  int listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }
}

class _Binding with LoadMoreControllerBinding {
  int calls = 0;
  bool throwNext = false;

  @override
  FutureOr<void> onLoadMore() {
    calls++;
    if (throwNext) {
      throwNext = false;
      throw StateError('load more failed');
    }
  }
}

void main() {
  group('LoadMoreControllerBinding', () {
    test('rebinding detaches the previous controller', () {
      final first = _CountingScrollController();
      final second = _CountingScrollController();
      final binding = _Binding();

      binding.addLoadMoreBinding(first);
      binding.addLoadMoreBinding(second);

      expect(first.listenerCount, equals(0));
      expect(second.listenerCount, equals(1));

      binding.removeLoadMoreBinding();
      expect(second.listenerCount, equals(0));

      first.dispose();
      second.dispose();
    });

    testWidgets('a throwing onLoadMore does not block later loads', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final binding = _Binding()..throwNext = true;

      // A short list: the end is always within the threshold.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(
            controller: controller,
            children: const [SizedBox(height: 10)],
          ),
        ),
      );
      binding.addLoadMoreBinding(controller);

      await expectLater(binding.loadMoreIfAvailable(), throwsStateError);
      await binding.loadMoreIfAvailable();

      expect(binding.calls, equals(2));
      binding.removeLoadMoreBinding();
    });
  });
}
