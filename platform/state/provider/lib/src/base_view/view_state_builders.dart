/// The builder signatures `BaseViewWidget` takes for each view state.
library;

import 'package:material_ui/material_ui.dart';

/// A typedef for building a widget when state is initial.
typedef InitialWidgetBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when state is empty.
typedef EmptyWidgetBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when state is loading.
typedef LoadingWidgetBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

/// A typedef for building a widget when the state is successful.
typedef SuccessWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
  Widget? child,
);

/// A typedef for building a widget when there is an error.
typedef ErrorWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
  String? message,
  Widget? child,
);
