import 'dart:async';

import 'package:domain_core/domain_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:platform_kernel/platform_kernel.dart';

import 'bloc_view_state.dart';

/// Adds [emitResult] to a Bloc whose state is [BlocViewState] — the BLoC
/// branch's counterpart of the Provider branch's `executeOperation`.
///
/// ```dart
/// @injectable
/// class OrdersBloc extends BaseBloc<OrdersEvent, BlocViewState<List<Order>>>
///     with BlocResultMixin<List<Order>> {
///   OrdersBloc(this._getOrders) : super(const BlocViewState.initial()) {
///     on<_OrdersRequested>(_onRequested);
///   }
///
///   final GetOrdersUseCase _getOrders;
///
///   Future<void> _onRequested(
///     _OrdersRequested event,
///     Emitter<BlocViewState<List<Order>>> emit,
///   ) => emitResult(emit, () => _getOrders(const NoParams()));
/// }
/// ```
///
/// See [emitResult] for the exact rules.
mixin BlocResultMixin<T> on BlocBase<BlocViewState<T>> {
  /// Runs [run] and settles the outcome into `BlocViewState<T>` through the
  /// handler's [emit]:
  ///
  /// | Outcome of [run]           | Emitted                                        |
  /// |:---------------------------|:-----------------------------------------------|
  /// | before it starts           | `loading` — only when [showLoading] and no `success` is on screen |
  /// | `Result.success(data)`     | `success(data)` (through [convert] when given) |
  /// | `Result.success(null)`     | `success(null)` when `T` is nullable, else `initial` |
  /// | `Result.failure(f)`        | `error(f)`                                     |
  /// | `Result.none` / `.cancel`  | the state before the call, if `loading` was emitted; otherwise nothing |
  /// | throws                     | `error(ErrorHandler.handleError(e))`, and the error is passed to `addError` (→ `BlocObserver.onError`) |
  ///
  /// [convert] maps a non-null payload `R` to `T`. Without it the payload
  /// must already be a `T`; anything else is a programming error and throws
  /// a [StateError].
  ///
  /// [onSuccess] / [onFailure] run after the state was emitted — use them
  /// for follow-up work (another event, analytics), not for state.
  ///
  /// Nothing is emitted once the handler is done — the bloc closed, or a
  /// `restartable()` transformer replaced this handler while [run] was
  /// pending — and the callbacks are then skipped too.
  @protected
  Future<void> emitResult<R>(
    Emitter<BlocViewState<T>> emit,
    Future<Result<R>> Function() run, {
    T Function(R data)? convert,
    bool showLoading = true,
    FutureOr<void> Function(T? data)? onSuccess,
    FutureOr<void> Function(AppFailure<dynamic> failure)? onFailure,
  }) => _settleResult<T, R>(
    current: state,
    emit: emit.call,
    isDone: () => isClosed || emit.isDone,
    reportError: addError,
    run: run,
    convert: convert,
    showLoading: showLoading,
    onSuccess: onSuccess,
    onFailure: onFailure,
  );
}

/// [BlocResultMixin] for a Cubit: the same rules, emitting through the
/// Cubit's own `emit`.
///
/// ```dart
/// class ProfileCubit extends BaseCubit<BlocViewState<User>>
///     with CubitResultMixin<User> {
///   ProfileCubit(this._getProfile) : super(const BlocViewState.initial());
///
///   final GetProfileUseCase _getProfile;
///
///   Future<void> load() => emitResult(() => _getProfile(const NoParams()));
/// }
/// ```
mixin CubitResultMixin<T> on Cubit<BlocViewState<T>> {
  /// See [BlocResultMixin.emitResult] — identical rules; nothing is emitted
  /// once the Cubit is closed.
  @protected
  Future<void> emitResult<R>(
    Future<Result<R>> Function() run, {
    T Function(R data)? convert,
    bool showLoading = true,
    FutureOr<void> Function(T? data)? onSuccess,
    FutureOr<void> Function(AppFailure<dynamic> failure)? onFailure,
  }) => _settleResult<T, R>(
    current: state,
    emit: emit,
    isDone: () => isClosed,
    reportError: addError,
    run: run,
    convert: convert,
    showLoading: showLoading,
    onSuccess: onSuccess,
    onFailure: onFailure,
  );
}

Future<void> _settleResult<T, R>({
  required BlocViewState<T> current,
  required void Function(BlocViewState<T> state) emit,
  required bool Function() isDone,
  required void Function(Object error, [StackTrace? stackTrace]) reportError,
  required Future<Result<R>> Function() run,
  required T Function(R data)? convert,
  required bool showLoading,
  required FutureOr<void> Function(T? data)? onSuccess,
  required FutureOr<void> Function(AppFailure<dynamic> failure)? onFailure,
}) async {
  if (isDone()) return;

  // Parity with `executeOperation`, which skips the spinner once data is
  // loaded: a refresh keeps the content on screen instead of blanking it.
  final isShowingContent = current.maybeWhen(
    success: (_) => true,
    orElse: () => false,
  );
  final emittedLoading = showLoading && !isShowingContent;
  // Never `const`: a const constructor cannot capture the type variable, so
  // `const BlocViewState.loading()` here would be a `BlocViewState<Never>`,
  // unequal to the `BlocViewState<T>.loading()` a view or test compares with.
  if (emittedLoading) emit(BlocViewState<T>.loading());

  Result<R> result;
  try {
    result = await run();
  } catch (error, stackTrace) {
    // Repositories already turn exceptions into `Result.failure`; one that
    // escapes is a bug. Still settle the screen — a handler that rethrew
    // here would leave it on `loading` — and surface the error to the
    // bloc's `onError` / `BlocObserver`.
    if (isDone()) return;
    reportError(error, stackTrace);
    result = Result.failure(ErrorHandler.handleError(error, stackTrace));
  }

  if (isDone()) return;

  switch (result) {
    case Success<R>(:final data):
      final value = _toState<T, R>(data, convert);
      emit(
        value is T
            ? BlocViewState<T>.success(value)
            : BlocViewState<T>.initial(),
      );
      if (isDone()) return;
      await onSuccess?.call(value);
    case Failure<R>(:final error):
      emit(BlocViewState<T>.error(error));
      if (isDone()) return;
      await onFailure?.call(error);
    case None<R>() || Cancel<R>():
      // No outcome to show: undo our own loading, touch nothing else.
      if (emittedLoading) emit(current);
  }
}

/// The success payload as a `T?`: `null` for no payload, [convert]ed when a
/// converter was given, otherwise the payload itself, which must be a `T`.
T? _toState<T, R>(R? data, T Function(R data)? convert) {
  if (data == null) return null;
  if (convert != null) return convert(data);
  if (data is T) return data as T;
  throw StateError(
    'emitResult: the operation returned ${data.runtimeType}, which is not the '
    'state type $T. Pass `convert` to map it.',
  );
}
