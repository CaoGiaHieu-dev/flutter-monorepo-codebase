// Barrel file for base_view module
// This file exports all the main components of the base_view module

import 'package:flutter/material.dart';

// Auto-generated exports, do not edit manually.
export 'base_proxy_widget.dart';
export 'base_view_widget.dart';
export 'default_state_widgets.dart';
export 'paginated_view_widget.dart';

/// A typedef for building a widget when state is initial.
typedef InitialWidgetBuilder<T> = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when state is empty.
typedef EmptyWidgetBuilder<T> = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when state is loading.
typedef LoadingWidgetBuilder<T> = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder2<T1, T2> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder3<T1, T2, T3> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder4<T1, T2, T3, T4> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder5<T1, T2, T3, T4, T5> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  T5 value5,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder6<T1, T2, T3, T4, T5, T6> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  T5 value5,
  T6 value6,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
  String? message,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder2<T1, T2> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  String? message1,
  String? message2,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder3<T1, T2, T3> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  String? message1,
  String? message2,
  String? message3,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder4<T1, T2, T3, T4> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  String? message1,
  String? message2,
  String? message3,
  String? message4,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder5<T1, T2, T3, T4, T5> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  T5 value5,
  String? message1,
  String? message2,
  String? message3,
  String? message4,
  String? message5,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder6<T1, T2, T3, T4, T5, T6> = Widget Function(
  BuildContext context,
  T1 value1,
  T2 value2,
  T3 value3,
  T4 value4,
  T5 value5,
  T6 value6,
  String? message1,
  String? message2,
  String? message3,
  String? message4,
  String? message5,
  String? message6,
  Widget? child,
);
