import 'package:material_ui/material_ui.dart' hide ErrorWidgetBuilder;

import '../base/base_provider.dart';
import 'default_state_widgets.dart';
import 'view_state_builders.dart';

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
    ViewStateModel<T> viewState,
    Widget? child,
  ) {
    return viewState.data == null
        ? emptyWidget?.call(context, child) ?? const DefaultEmptyWidget()
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
