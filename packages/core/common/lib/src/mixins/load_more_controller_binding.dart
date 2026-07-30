import 'dart:async';

import 'package:flutter/material.dart';

///  Mixin class for binding a [ScrollController] to load more functionality.
///
/// This mixin simplifies the process of implementing load more functionality
/// in your Flutter applications by handling the logic of monitoring the scroll position
/// and calling the `onLoadMore` method when the user reaches the end of the list.
///
/// Example of how to use the LoadMoreControllerBinding mixin:
///
/// ```dart
/// class MyListView extends StatefulWidget {
///   @override
///   _MyListViewState createState() => _MyListViewState();
/// }
///
/// class _MyListViewState extends State<MyListView>
///     with LoadMoreControllerBinding {
///   final ScrollController _scrollController = ScrollController();
///   List<String> _items = ['Item 1', 'Item 2', 'Item 3'];
///
///   @override
///   void initState() {
///     super.initState();
///     addLoadMoreBinding(_scrollController);
///   }
///
///   @override
///   void dispose() {
///     removeLoadMoreBinding();
///     _scrollController.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return ListView.builder(
///       controller: _scrollController,
///       itemCount: _items.length,
///       itemBuilder: (context, index) {
///         return ListTile(
///           title: Text(_items[index]),
///         );
///       },
///     );
///   }
///
///   @override
///   void onLoadMore() {
///     // Load more items here
///     setState(() {
///       _items.addAll(['Item ${_items.length + 1}', 'Item ${_items.length + 2}']);
///     });
///   }
/// }
/// ```
abstract mixin class LoadMoreControllerBinding {
  /// Flag to track if load more operation is in progress.
  var _isLoadMore = false;

  /// The [ScrollController] associated with the list view.
  ScrollController? _scrollController;

  /// The [ScrollPosition] of the [ScrollController].
  ScrollPosition? get _position => _scrollController?.position;

  /// The distance to load more.
  double get loadMoreThreshold => 200.0;

  /// Adds a load more binding to the given [ScrollController].
  ///
  /// This method should be called whenever the [ScrollController]
  /// of a list view is created or changed.
  ///
  /// **Arguments:**
  /// * `scroll`: The [ScrollController] to bind to.
  void addLoadMoreBinding(ScrollController scroll) {
    // Reset the current scroll controller
    _scrollController = null;
    // Assign the new scroll controller
    _scrollController = scroll;
    // Add a listener to the scroll controller
    _scrollController?.addListener(loadMoreIfAvailable);
  }

  /// Removes the load more binding from the [ScrollController].
  ///
  /// This method should be called when the list view is disposed.
  void removeLoadMoreBinding() {
    // Remove the listener from the scroll controller
    _scrollController?.removeListener(loadMoreIfAvailable);
    // Reset the scroll controller
    _scrollController = null;
  }

  /// Listener function for the [ScrollController].
  ///
  /// This method is called whenever the scroll position changes.
  /// It checks if the user has scrolled to the end of the list
  /// and calls the `onLoadMore` method if they have.
  Future<void> loadMoreIfAvailable() async {
    // Return early if the scroll position is null
    if (_position == null) return;

    // Prevent multiple load more operations
    if (_isLoadMore) return;
    _isLoadMore = true;

    // Check if the user has scrolled to the end of the list
    if (_position!.pixels >= _position!.maxScrollExtent - loadMoreThreshold) {
      // Call the onLoadMore method
      await onLoadMore.call();
    }

    // Allow subsequent load more operation
    _isLoadMore = false;
  }

  /// Method called when the user reaches the end of the list.
  ///
  /// This method should be implemented in the class that extends this mixin.
  /// It is responsible for loading more data or performing other actions.
  FutureOr<void> onLoadMore();
}
