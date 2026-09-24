import 'package:flutter/foundation.dart';

/// A mixin that provides load more functionality to a [ChangeNotifier].
///
/// This mixin uses a [ScrollController] to listen for scroll events and trigger
/// the `onLoadMore` method when the user scrolls to the bottom of the list.
///
/// The `onLoadMore` method should be overridden to handle the loading of more
/// data. This mixin provides the following properties and methods to help with
/// load more functionality:
///
/// - `totalPage`: The total number of pages in the data set.
/// - `currentPage`: The current page being displayed.
/// - `nextPage`: The next page to load.
/// - `isLoadingMore`: Whether the mixin is currently loading more data.
/// - `canLoadMore`: Whether the mixin can load more data.
/// - `listenLoadMore()`: Adds a listener to the [ScrollController] to trigger
///   `onLoadMore` when the user scrolls to the bottom of the list.
/// - `removeListenLoadMore()`: Removes the listener from the [ScrollController].
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
