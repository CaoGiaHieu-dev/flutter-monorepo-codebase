import 'package:domain_core/domain_core.dart';
import 'package:flutter/material.dart' hide ErrorWidgetBuilder;

import '../../provider_state_management.dart';

/// A base widget that listens to a provider and builds different widgets
/// based on the state of the provider with PaginatedEntity.
class PaginatedViewWidget<
  P extends BaseProvider<PaginatedEntity<T>>,
  T extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget({
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
  final SuccessWidgetBuilder<PaginatedEntity<T>> builder;

  /// The builder function to be called when there is an error.
  final ErrorWidgetBuilder<PaginatedEntity<T>?>? onErrorBuilder;

  /// The widget to be displayed when the state is initial.
  final InitialWidgetBuilder? initialWidget;

  /// The widget to be displayed when the state is loading.
  final LoadingWidgetBuilder? loadingWidget;

  /// The widget to be displayed when the state is empty.
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T>> viewState,
    Widget? child,
  ) {
    final data = viewState.data;
    return data == null || data.data.isEmpty
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
        : builder.call(context, data, child);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<P, ViewStateModel<PaginatedEntity<T>>>(
      selector: (context, provider) {
        return provider.viewState;
      },
      builder: (context, viewState, child) {
        final builder = _builder(context, viewState, child);
        return viewState.state.maybeWhen(
          initial: () =>
              initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget(),
          loading: () =>
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget(),
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
/// based on the state of the providers with PaginatedEntity.
class PaginatedViewWidget2<
  P1 extends BaseProvider<PaginatedEntity<T1>>,
  T1 extends Object,
  P2 extends BaseProvider<PaginatedEntity<T2>>,
  T2 extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget2({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder2<PaginatedEntity<T1>?, PaginatedEntity<T2>?>
  builder;
  final ErrorWidgetBuilder2<PaginatedEntity<T1>?, PaginatedEntity<T2>?>?
  onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T1>> viewState1,
    ViewStateModel<PaginatedEntity<T2>> viewState2,
    Widget? child,
  ) {
    return (viewState1.data == null || viewState1.data!.data.isEmpty) &&
            (viewState2.data == null || viewState2.data!.data.isEmpty)
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
        : builder.call(context, viewState1.data, viewState2.data, child);
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<
      P1,
      P2,
      ({
        ViewStateModel<PaginatedEntity<T1>> viewState1,
        ViewStateModel<PaginatedEntity<T2>> viewState2,
      })
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
          return loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
        } else if (viewState1.isInitial || viewState2.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
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
/// based on the state of the providers with PaginatedEntity.
class PaginatedViewWidget3<
  P1 extends BaseProvider<PaginatedEntity<T1>>,
  T1 extends Object,
  P2 extends BaseProvider<PaginatedEntity<T2>>,
  T2 extends Object,
  P3 extends BaseProvider<PaginatedEntity<T3>>,
  T3 extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget3({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder3<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?
  >
  builder;
  final ErrorWidgetBuilder3<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?
  >?
  onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T1>> viewState1,
    ViewStateModel<PaginatedEntity<T2>> viewState2,
    ViewStateModel<PaginatedEntity<T3>> viewState3,
    Widget? child,
  ) {
    return (viewState1.data == null || viewState1.data!.data.isEmpty) &&
            (viewState2.data == null || viewState2.data!.data.isEmpty) &&
            (viewState3.data == null || viewState3.data!.data.isEmpty)
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
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
        ViewStateModel<PaginatedEntity<T1>> viewState1,
        ViewStateModel<PaginatedEntity<T2>> viewState2,
        ViewStateModel<PaginatedEntity<T3>> viewState3,
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
          return loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
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
/// based on the state of the providers with PaginatedEntity.
class PaginatedViewWidget4<
  P1 extends BaseProvider<PaginatedEntity<T1>>,
  T1 extends Object,
  P2 extends BaseProvider<PaginatedEntity<T2>>,
  T2 extends Object,
  P3 extends BaseProvider<PaginatedEntity<T3>>,
  T3 extends Object,
  P4 extends BaseProvider<PaginatedEntity<T4>>,
  T4 extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget4({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder4<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?
  >
  builder;
  final ErrorWidgetBuilder4<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?
  >?
  onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T1>> viewState1,
    ViewStateModel<PaginatedEntity<T2>> viewState2,
    ViewStateModel<PaginatedEntity<T3>> viewState3,
    ViewStateModel<PaginatedEntity<T4>> viewState4,
    Widget? child,
  ) {
    return (viewState1.data == null || viewState1.data!.data.isEmpty) &&
            (viewState2.data == null || viewState2.data!.data.isEmpty) &&
            (viewState3.data == null || viewState3.data!.data.isEmpty) &&
            (viewState4.data == null || viewState4.data!.data.isEmpty)
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
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
        ViewStateModel<PaginatedEntity<T1>> viewState1,
        ViewStateModel<PaginatedEntity<T2>> viewState2,
        ViewStateModel<PaginatedEntity<T3>> viewState3,
        ViewStateModel<PaginatedEntity<T4>> viewState4,
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
          return loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
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
/// based on the state of the providers with PaginatedEntity.
class PaginatedViewWidget5<
  P1 extends BaseProvider<PaginatedEntity<T1>>,
  T1 extends Object,
  P2 extends BaseProvider<PaginatedEntity<T2>>,
  T2 extends Object,
  P3 extends BaseProvider<PaginatedEntity<T3>>,
  T3 extends Object,
  P4 extends BaseProvider<PaginatedEntity<T4>>,
  T4 extends Object,
  P5 extends BaseProvider<PaginatedEntity<T5>>,
  T5 extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget5({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder5<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?,
    PaginatedEntity<T5>?
  >
  builder;
  final ErrorWidgetBuilder5<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?,
    PaginatedEntity<T5>?
  >?
  onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T1>> viewState1,
    ViewStateModel<PaginatedEntity<T2>> viewState2,
    ViewStateModel<PaginatedEntity<T3>> viewState3,
    ViewStateModel<PaginatedEntity<T4>> viewState4,
    ViewStateModel<PaginatedEntity<T5>> viewState5,
    Widget? child,
  ) {
    return (viewState1.data == null || viewState1.data!.data.isEmpty) &&
            (viewState2.data == null || viewState2.data!.data.isEmpty) &&
            (viewState3.data == null || viewState3.data!.data.isEmpty) &&
            (viewState4.data == null || viewState4.data!.data.isEmpty) &&
            (viewState5.data == null || viewState5.data!.data.isEmpty)
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
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
        ViewStateModel<PaginatedEntity<T1>> viewState1,
        ViewStateModel<PaginatedEntity<T2>> viewState2,
        ViewStateModel<PaginatedEntity<T3>> viewState3,
        ViewStateModel<PaginatedEntity<T4>> viewState4,
        ViewStateModel<PaginatedEntity<T5>> viewState5,
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
          return loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial ||
            viewState5.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
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
/// based on the state of the providers with PaginatedEntity.
class PaginatedViewWidget6<
  P1 extends BaseProvider<PaginatedEntity<T1>>,
  T1 extends Object,
  P2 extends BaseProvider<PaginatedEntity<T2>>,
  T2 extends Object,
  P3 extends BaseProvider<PaginatedEntity<T3>>,
  T3 extends Object,
  P4 extends BaseProvider<PaginatedEntity<T4>>,
  T4 extends Object,
  P5 extends BaseProvider<PaginatedEntity<T5>>,
  T5 extends Object,
  P6 extends BaseProvider<PaginatedEntity<T6>>,
  T6 extends Object
>
    extends StatelessWidget {
  const PaginatedViewWidget6({
    super.key,
    required this.builder,
    this.child,
    this.onErrorBuilder,
    this.initialWidget,
    this.loadingWidget,
    this.emptyWidget,
  });

  final Widget? child;
  final SuccessWidgetBuilder6<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?,
    PaginatedEntity<T5>?,
    PaginatedEntity<T6>?
  >
  builder;
  final ErrorWidgetBuilder6<
    PaginatedEntity<T1>?,
    PaginatedEntity<T2>?,
    PaginatedEntity<T3>?,
    PaginatedEntity<T4>?,
    PaginatedEntity<T5>?,
    PaginatedEntity<T6>?
  >?
  onErrorBuilder;
  final InitialWidgetBuilder? initialWidget;
  final LoadingWidgetBuilder? loadingWidget;
  final EmptyWidgetBuilder? emptyWidget;

  Widget _builder(
    BuildContext context,
    ViewStateModel<PaginatedEntity<T1>> viewState1,
    ViewStateModel<PaginatedEntity<T2>> viewState2,
    ViewStateModel<PaginatedEntity<T3>> viewState3,
    ViewStateModel<PaginatedEntity<T4>> viewState4,
    ViewStateModel<PaginatedEntity<T5>> viewState5,
    ViewStateModel<PaginatedEntity<T6>> viewState6,
    Widget? child,
  ) {
    return (viewState1.data == null || viewState1.data!.data.isEmpty) &&
            (viewState2.data == null || viewState2.data!.data.isEmpty) &&
            (viewState3.data == null || viewState3.data!.data.isEmpty) &&
            (viewState4.data == null || viewState4.data!.data.isEmpty) &&
            (viewState5.data == null || viewState5.data!.data.isEmpty) &&
            (viewState6.data == null || viewState6.data!.data.isEmpty)
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
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
        ViewStateModel<PaginatedEntity<T1>> viewState1,
        ViewStateModel<PaginatedEntity<T2>> viewState2,
        ViewStateModel<PaginatedEntity<T3>> viewState3,
        ViewStateModel<PaginatedEntity<T4>> viewState4,
        ViewStateModel<PaginatedEntity<T5>> viewState5,
        ViewStateModel<PaginatedEntity<T6>> viewState6,
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
          return loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
        } else if (viewState1.isInitial ||
            viewState2.isInitial ||
            viewState3.isInitial ||
            viewState4.isInitial ||
            viewState5.isInitial ||
            viewState6.isInitial) {
          return initialWidget?.call(context, child) ??
              loadingWidget?.call(context, child) ??
              const DefaultLoadingWidget();
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
