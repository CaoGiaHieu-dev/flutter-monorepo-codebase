import 'package:flutter/foundation.dart';

/// A mixin that tracks pagination state for a [ChangeNotifier].
///
/// The mixin holds no scroll logic: the list widget (see `LoadMoreListView`)
/// decides when the user reached the end and asks for the next page, while
/// this mixin only answers whether one is available. It provides:
///
/// - `totalPage`: The total number of pages in the data set.
/// - `currentPage`: The current page being displayed.
/// - `nextPage`: The next page to load.
/// - `isLoadingMore`: Whether the mixin is currently loading more data.
/// - `canLoadMore`: Whether another page can be requested right now.
/// - `setTotalPage(int value)`: Sets the total number of pages.
/// - `setCurrentPage(int value)`: Sets the current page.
mixin LoadMoreMixin<T> on ChangeNotifier {
  /// The total number of pages in the data set.
  var totalPage = 0;

  /// The current page being displayed.
  var currentPage = 0;

  /// The next page to load.
  int get nextPage => currentPage + 1;

  /// Whether the mixin is currently loading more data.
  var _isLoadingMore = false;

  /// Whether the mixin is currently loading more data.
  bool get isLoadingMore => _isLoadingMore;

  /// Sets whether the mixin is currently loading more data.
  ///
  /// This method notifies listeners when the value changes.
  set isLoadingMore(bool value) {
    _isLoadingMore = value;
    notifyListeners();
  }

  /// Whether the mixin can load more data.
  bool get canLoadMore => !isLoadingMore && nextPage <= totalPage;

  /// Sets the total number of pages.
  void setTotalPage(int value) {
    totalPage = value;
  }

  /// Sets the current page.
  void setCurrentPage(int value) {
    currentPage = value;
  }
}
