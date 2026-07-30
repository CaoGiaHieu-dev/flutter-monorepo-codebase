part of '../base/base_provider.dart';

/// Manages view state changes and notifications
///
/// This class is responsible for managing the state of a provider,
/// including state transitions, data updates, and notifying listeners.
///
/// Features:
/// - State management with ViewStateModel
/// - Stream-based state broadcasting
/// - Automatic disposal handling
/// - Thread-safe state updates
class StateManager<T> extends ChangeNotifier {
  StateManager()
    : _viewState = ViewStateModel<T>(state: const ViewState.initial());

  final _streamController = StreamController<ViewStateModel<T>>.broadcast();

  ViewStateModel<T> _viewState;
  bool _isDisposed = false;

  /// Current view state
  ViewStateModel<T> get viewState => _viewState;

  /// Stream of view state changes for reactive programming
  Stream<ViewStateModel<T>> get stateStream => _streamController.stream;

  /// Current data from the view state
  T? get data => _viewState.data;

  /// Check if currently in loading state
  bool get isLoading => _viewState.isLoading;

  /// Check if currently in success state
  bool get isSuccess => _viewState.isSuccess;

  /// Check if currently in error state
  bool get isError => _viewState.isError;

  /// Check if state manager is disposed
  bool get isDisposed => _isDisposed;

  /// Update the view state with a new ViewStateModel
  ///
  /// This method updates the internal state and notifies all listeners
  /// including both ChangeNotifier listeners and stream subscribers.
  void updateState(ViewStateModel<T> newState) {
    if (_isDisposed || _viewState == newState) return;

    _viewState = newState;
    notifyListeners();
    _streamController.add(newState);
  }

  /// Update state with individual parameters
  ///
  /// This is a convenience method that allows updating specific
  /// parts of the state without creating a new ViewStateModel manually.
  ///
  /// Parameters:
  /// - [state]: New state to set
  /// - [data]: New data to set
  /// - [message]: New message to set
  /// - [retainOldData]: Whether to keep existing data if no new data provided
  void setState({
    ViewState? state,
    T? data,
    String? message,
    bool retainOldData = true,
  }) {
    final newData = data ?? (retainOldData ? _viewState.data : null);

    updateState(
      _viewState.copyWith(
        state: state ?? _viewState.state,
        data: newData,
        message: message,
      ),
    );
  }

  /// Set data directly without changing state
  ///
  /// This method allows updating just the data while keeping
  /// the current state and message unchanged.
  void setData(T? data) {
    setState(data: data);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _streamController.close();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
}
