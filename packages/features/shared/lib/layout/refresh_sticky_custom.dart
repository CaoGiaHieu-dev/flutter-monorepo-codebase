import 'dart:async';

import 'package:core_base_ui/core_base_ui.dart';
import 'package:flutter/material.dart';
import 'package:jumping_dot/jumping_dot.dart';
import 'package:refresh_sticky/refresh_sticky.dart';

/// A custom widget that extends the `RefreshSticky` widget to provide a more
/// visually appealing and customizable refresh experience.
///
/// This widget provides a builder function that allows you to customize the
/// content displayed when the user pulls down to refresh. The widget also
/// provides a loading indicator that is displayed while the refresh operation
/// is in progress.
///
/// **Example:**
/// ```dart
/// RefreshStickyCustom(
///   onRefresh: () async {
///     // Your refresh logic here
///   },
///   builder: (context, controller) {
///     return ListView.builder(
///       controller: controller,
///       itemCount: 10,
///       itemBuilder: (context, index) {
///         return ListTile(
///           title: Text('Item $index'),
///         );
///       },
///     );
///   },
/// );
/// ```
class RefreshStickyCustom extends StatelessWidget {
  /// Creates a `RefreshStickyCustom` widget.
  ///
  /// The `builder` function is required and takes the `BuildContext` and the
  /// `ScrollController` as arguments. This function should return the widget
  /// that you want to display in the refresh area.
  ///
  /// The `onRefresh` function is also required and should return a `Future`
  /// that resolves when the refresh operation is complete.
  ///
  /// The `controller` parameter is optional and can be used to provide a custom
  /// `ScrollController` to the `RefreshSticky` widget.
  const RefreshStickyCustom({
    super.key,
    required this.builder,
    this.controller,
    required this.onRefresh,
    this.reverse = false,
  });

  /// The builder function that returns the widget to be displayed in the
  /// refresh area.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  /// The callback function that is called when the user pulls down to refresh.
  /// This function should return a `Future` that resolves when the refresh
  /// operation is complete.
  final Future<void> Function() onRefresh;

  final bool reverse;

  /// The optional `ScrollController` to be used for the `RefreshSticky` widget.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return RefreshSticky(
      reverse: reverse,

      /// The size of the refresh indicator in pixels.
      size: 30,

      /// The controller for the scroll view.
      controller: controller,

      /// The scale factor for the loading icon.
      scaleLoadingIcon: 1.5,

      /// The builder function that returns the widget to be displayed while the
      /// refresh operation is in progress.
      loadingBuilder: (context) {
        return JumpingDots(
          /// The color of the dots.
          color: context.primary,

          /// The radius of the dots.
          radius: 10,

          /// The vertical offset of the dots.
          verticalOffset: 10,

          /// The number of dots to display.
          numberOfDots: 3,
        );
      },

      /// The builder function that returns the widget to be displayed before
      /// the refresh operation begins.
      preLoadingBuilder: (context) {
        return Row(
          children: List.generate(
            /// The number of dots to display.
            3,
            (index) => Expanded(
              /// The size of the dot.
              child: DotWidget(
                /// The color of the dot.
                color: context.primary,

                /// The radius of the dot.
                radius: 10,
              ),
            ),
          ).toList(),
        );
      },

      /// The callback function that is called when the user pulls down to refresh.
      /// This function should return a `Future` that resolves when the refresh
      /// operation is complete.
      onRefresh: () async {
        await onRefresh();
      },

      /// The builder function that returns the widget to be displayed in the
      /// refresh area.
      builder: builder,
    );
  }
}
