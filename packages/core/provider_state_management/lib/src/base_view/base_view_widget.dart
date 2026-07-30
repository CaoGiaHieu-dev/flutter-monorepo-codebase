import 'package:feature_shared/feature_shared.dart';
import 'package:flutter/material.dart' hide ErrorWidgetBuilder;

import '../../provider_state_management.dart';

/// A base widget that listens to a provider and builds different widgets
/// based on the state of the provider.
class BaseViewWidget<P extends BaseProvider<T>, T extends Object>
    extends StatelessWidget {
  const BaseViewWidget({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  /// The child widget to be passed to the builder.
  final Widget? child;

  /// The builder function to be called when the state is successful.
  final SuccessWidgetBuilder<T> builder;

  /// The builder function to be called when there is an error.
  final ErrorWidgetBuilder<T?>? onErrorBuilder;

  /// The widget to be displayed when the state is initial.
  final InitialWidgetBuilder? initialWidget;

  /// The widget to be displayed when the state is loading.
  final LoadingWidgetBuilder? loadingWidget;

  /// The widget to be displayed when the state is empty.
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState,
    Widget? child,
  ) {
    return viewState.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(context, viewState.data!, child);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<P, ViewStateModel<T>>(
      selector: (context, provider) {
        return provider.viewState;
      },
      builder: (context, viewState, child) {
        final builder = _builder(context, viewState, child);
        return viewState.state.maybeWhen(
          initial: () =>
              initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget(),
          loading: () =>
              loadingWidget?.call(context, child) ?? const LoadingWidget(),
          error: (error) =>
              onErrorBuilder?.call(
                context,
                viewState.data,
                viewState.message,
                child,
              ) ??
              builder,
          orElse: () => builder,
        );
      },
      child: child,
    );
  }
}

/// A base widget that listens to two providers and builds different widgets
/// based on the state of the providers.
class BaseViewWidget2<
  P1 extends BaseProvider<T1>,
  T1 extends Object,
  P2 extends BaseProvider<T2>,
  T2 extends Object
>
    extends StatelessWidget {
  const BaseViewWidget2({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder2<T1?, T2?> builder;
  final ErrorWidgetBuilder2<T1?, T2?>? onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState1,
    ViewStateModel viewState2,
    Widget? child,
  ) {
    return viewState1.data == null && viewState2.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(context, viewState1.data, viewState2.data, child);
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<
      P1,
      P2,
      ({ViewStateModel<T1> viewState1, ViewStateModel<T2> viewState2})
    >(
      selector: (context, provider1, provider2) {
        // Combine the states of both providers as needed
        return (
          viewState1: provider1.viewState,
          viewState2: provider2.viewState,
        ); // or any logic to combine states
      },
      builder: (context, viewState, child) {
        final viewState1 = viewState.viewState1;
        final viewState2 = viewState.viewState2;
        final builder = _builder(context, viewState1, viewState2, child);
        if (viewState1.isLoading || viewState2.isLoading) {
          return loadingWidget?.call(context, child) ?? const LoadingWidget();
        } else if (viewState1.isInitial || viewState2.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget();
        } else if (viewState1.isError || viewState2.isError) {
          return onErrorBuilder?.call(
                context,
                viewState1.data,
                viewState2.data,
                viewState1.message,
                viewState2.message,
                child,
              ) ??
              builder;
        }

        return builder;
      },
      child: child,
    );
  }
}

/// A base widget that listens to three providers and builds different widgets
/// based on the state of the providers.
class BaseViewWidget3<
  P1 extends BaseProvider<T1>,
  T1 extends Object,
  P2 extends BaseProvider<T2>,
  T2 extends Object,
  P3 extends BaseProvider<T3>,
  T3 extends Object
>
    extends StatelessWidget {
  const BaseViewWidget3({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder3<T1?, T2?, T3?> builder;
  final ErrorWidgetBuilder3<T1?, T2?, T3?>? onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState1,
    ViewStateModel viewState2,
    ViewStateModel viewState3,
    Widget? child,
  ) {
    return viewState1.data == null &&
            viewState2.data == null &&
            viewState3.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(
            context,
            viewState1.data,
            viewState2.data,
            viewState3.data,
            child,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Selector3<
      P1,
      P2,
      P3,
      ({
        ViewStateModel<T1> viewState1,
        ViewStateModel<T2> viewState2,
        ViewStateModel<T3> viewState3,
      })
    >(
      selector: (context, provider1, provider2, provider3) {
        // Combine the states of all three providers as needed
        return (
          viewState1: provider1.viewState,
          viewState2: provider2.viewState,
          viewState3: provider3.viewState,
        ); // or any logic to combine states
      },
      builder: (context, viewState, child) {
        final viewState1 = viewState.viewState1;
        final viewState2 = viewState.viewState2;
        final viewState3 = viewState.viewState3;
        final builder = _builder(
          context,
          viewState1,
          viewState2,
          viewState3,
          child,
        );
        if (viewState1.isLoading ||
            viewState2.isLoading ||
            viewState3.isLoading) {
          return loadingWidget?.call(context, child) ?? const LoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget();
        } else if (viewState1.isError ||
            viewState2.isError ||
            viewState3.isError) {
          return onErrorBuilder?.call(
                context,
                viewState1.data,
                viewState2.data,
                viewState3.data,
                viewState1.message,
                viewState2.message,
                viewState3.message,
                child,
              ) ??
              builder;
        }

        return builder;
      },
      child: child,
    );
  }
}

/// A base widget that listens to four providers and builds different widgets
/// based on the state of the providers.
class BaseViewWidget4<
  P1 extends BaseProvider<T1>,
  T1 extends Object,
  P2 extends BaseProvider<T2>,
  T2 extends Object,
  P3 extends BaseProvider<T3>,
  T3 extends Object,
  P4 extends BaseProvider<T4>,
  T4 extends Object
>
    extends StatelessWidget {
  const BaseViewWidget4({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder4<T1?, T2?, T3?, T4?> builder;
  final ErrorWidgetBuilder4<T1?, T2?, T3?, T4?>? onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState1,
    ViewStateModel viewState2,
    ViewStateModel viewState3,
    ViewStateModel viewState4,
    Widget? child,
  ) {
    return viewState1.data == null &&
            viewState2.data == null &&
            viewState3.data == null &&
            viewState4.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(
            context,
            viewState1.data,
            viewState2.data,
            viewState3.data,
            viewState4.data,
            child,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Selector4<
      P1,
      P2,
      P3,
      P4,
      ({
        ViewStateModel<T1> viewState1,
        ViewStateModel<T2> viewState2,
        ViewStateModel<T3> viewState3,
        ViewStateModel<T4> viewState4,
      })
    >(
      selector: (context, provider1, provider2, provider3, provider4) {
        // Combine the states of all four providers as needed
        return (
          viewState1: provider1.viewState,
          viewState2: provider2.viewState,
          viewState3: provider3.viewState,
          viewState4: provider4.viewState,
        ); // or any logic to combine states
      },
      builder: (context, viewState, child) {
        final viewState1 = viewState.viewState1;
        final viewState2 = viewState.viewState2;
        final viewState3 = viewState.viewState3;
        final viewState4 = viewState.viewState4;
        final builder = _builder(
          context,
          viewState1,
          viewState2,
          viewState3,
          viewState4,
          child,
        );
        if (viewState1.isLoading ||
            viewState2.isLoading ||
            viewState3.isLoading ||
            viewState4.isLoading) {
          return loadingWidget?.call(context, child) ?? const LoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget();
        } else if (viewState1.isError ||
            viewState2.isError ||
            viewState3.isError ||
            viewState4.isError) {
          return onErrorBuilder?.call(
                context,
                viewState1.data,
                viewState2.data,
                viewState3.data,
                viewState4.data,
                viewState1.message,
                viewState2.message,
                viewState3.message,
                viewState4.message,
                child,
              ) ??
              builder;
        }

        return builder;
      },
      child: child,
    );
  }
}

/// A base widget that listens to five providers and builds different widgets
/// based on the state of the providers.
class BaseViewWidget5<
  P1 extends BaseProvider<T1>,
  T1 extends Object,
  P2 extends BaseProvider<T2>,
  T2 extends Object,
  P3 extends BaseProvider<T3>,
  T3 extends Object,
  P4 extends BaseProvider<T4>,
  T4 extends Object,
  P5 extends BaseProvider<T5>,
  T5 extends Object
>
    extends StatelessWidget {
  const BaseViewWidget5({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder5<T1?, T2?, T3?, T4?, T5?> builder;
  final ErrorWidgetBuilder5<T1?, T2?, T3?, T4?, T5?>? onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState1,
    ViewStateModel viewState2,
    ViewStateModel viewState3,
    ViewStateModel viewState4,
    ViewStateModel viewState5,
    Widget? child,
  ) {
    return viewState1.data == null &&
            viewState2.data == null &&
            viewState3.data == null &&
            viewState4.data == null &&
            viewState5.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(
            context,
            viewState1.data,
            viewState2.data,
            viewState3.data,
            viewState4.data,
            viewState5.data,
            child,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Selector5<
      P1,
      P2,
      P3,
      P4,
      P5,
      ({
        ViewStateModel<T1> viewState1,
        ViewStateModel<T2> viewState2,
        ViewStateModel<T3> viewState3,
        ViewStateModel<T4> viewState4,
        ViewStateModel<T5> viewState5,
      })
    >(
      selector:
          (context, provider1, provider2, provider3, provider4, provider5) {
            // Combine the states of all five providers as needed
            return (
              viewState1: provider1.viewState,
              viewState2: provider2.viewState,
              viewState3: provider3.viewState,
              viewState4: provider4.viewState,
              viewState5: provider5.viewState,
            ); // or any logic to combine states
          },
      builder: (context, viewState, child) {
        final viewState1 = viewState.viewState1;
        final viewState2 = viewState.viewState2;
        final viewState3 = viewState.viewState3;
        final viewState4 = viewState.viewState4;
        final viewState5 = viewState.viewState5;
        final builder = _builder(
          context,
          viewState1,
          viewState2,
          viewState3,
          viewState4,
          viewState5,
          child,
        );
        if (viewState1.isLoading ||
            viewState2.isLoading ||
            viewState3.isLoading ||
            viewState4.isLoading ||
            viewState5.isLoading) {
          return loadingWidget?.call(context, child) ?? const LoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial ||
            viewState5.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget();
        } else if (viewState1.isError ||
            viewState2.isError ||
            viewState3.isError ||
            viewState4.isError ||
            viewState5.isError) {
          return onErrorBuilder?.call(
                context,
                viewState1.data,
                viewState2.data,
                viewState3.data,
                viewState4.data,
                viewState5.data,
                viewState1.message,
                viewState2.message,
                viewState3.message,
                viewState4.message,
                viewState5.message,
                child,
              ) ??
              builder;
        }

        return builder;
      },
      child: child,
    );
  }
}

/// A base widget that listens to six providers and builds different widgets
/// based on the state of the providers.
class BaseViewWidget6<
  P1 extends BaseProvider<T1>,
  T1 extends Object,
  P2 extends BaseProvider<T2>,
  T2 extends Object,
  P3 extends BaseProvider<T3>,
  T3 extends Object,
  P4 extends BaseProvider<T4>,
  T4 extends Object,
  P5 extends BaseProvider<T5>,
  T5 extends Object,
  P6 extends BaseProvider<T6>,
  T6 extends Object
>
    extends StatelessWidget {
  const BaseViewWidget6({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder6<T1?, T2?, T3?, T4?, T5?, T6?> builder;
  final ErrorWidgetBuilder6<T1?, T2?, T3?, T4?, T5?, T6?>? onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel viewState1,
    ViewStateModel viewState2,
    ViewStateModel viewState3,
    ViewStateModel viewState4,
    ViewStateModel viewState5,
    ViewStateModel viewState6,
    Widget? child,
  ) {
    return viewState1.data == null &&
            viewState2.data == null &&
            viewState3.data == null &&
            viewState4.data == null &&
            viewState5.data == null &&
            viewState6.data == null
        ? emptyWidget?.call(context, child) ?? const EmptyWidget()
        : builder.call(
            context,
            viewState1.data,
            viewState2.data,
            viewState3.data,
            viewState4.data,
            viewState5.data,
            viewState6.data,
            child,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Selector6<
      P1,
      P2,
      P3,
      P4,
      P5,
      P6,
      ({
        ViewStateModel<T1> viewState1,
        ViewStateModel<T2> viewState2,
        ViewStateModel<T3> viewState3,
        ViewStateModel<T4> viewState4,
        ViewStateModel<T5> viewState5,
        ViewStateModel<T6> viewState6,
      })
    >(
      selector:
          (
            context,
            provider1,
            provider2,
            provider3,
            provider4,
            provider5,
            provider6,
          ) {
            // Combine the states of all six providers as needed
            return (
              viewState1: provider1.viewState,
              viewState2: provider2.viewState,
              viewState3: provider3.viewState,
              viewState4: provider4.viewState,
              viewState5: provider5.viewState,
              viewState6: provider6.viewState,
            ); // or any logic to combine states
          },
      builder: (context, viewState, child) {
        final viewState1 = viewState.viewState1;
        final viewState2 = viewState.viewState2;
        final viewState3 = viewState.viewState3;
        final viewState4 = viewState.viewState4;
        final viewState5 = viewState.viewState5;
        final viewState6 = viewState.viewState6;
        final builder = _builder(
          context,
          viewState1,
          viewState2,
          viewState3,
          viewState4,
          viewState5,
          viewState6,
          child,
        );
        if (viewState1.isLoading ||
            viewState2.isLoading ||
            viewState3.isLoading ||
            viewState4.isLoading ||
            viewState5.isLoading ||
            viewState6.isLoading) {
          return loadingWidget?.call(context, child) ?? const LoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial ||
            viewState5.isInitial ||
            viewState6.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const LoadingWidget();
        } else if (viewState1.isError ||
            viewState2.isError ||
            viewState3.isError ||
            viewState4.isError ||
            viewState5.isError ||
            viewState6.isError) {
          return onErrorBuilder?.call(
                context,
                viewState1.data,
                viewState2.data,
                viewState3.data,
                viewState4.data,
                viewState5.data,
                viewState6.data,
                viewState1.message,
                viewState2.message,
                viewState3.message,
                viewState4.message,
                viewState5.message,
                viewState6.message,
                child,
              ) ??
              builder;
        }

        return builder;
      },
      child: child,
    );
  }
}
