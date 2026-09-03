import 'package:cupertino_ui/cupertino_ui.dart';

/// Mixin to listen to and handle app lifecycle events.
///
/// This mixin provides methods to start and stop listening to app lifecycle events.
/// It also defines methods for handling specific lifecycle events, such as `onResume`,
/// `onHide`, `onPause`, `onDetach`, `onInactive`, `onRestart`, `onShow`, and `onStateChange`.
///
/// To use this mixin, simply extend your widget with this mixin and override the
/// desired methods to handle the corresponding lifecycle events.
///
/// Example usage:
///
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   _MyWidgetState createState() => _MyWidgetState();
/// }
///
/// class _MyWidgetState extends State<MyWidget> with LifecycleMixin {
///   @override
///   void initState() {
///     super.initState();
///     startListenOnLifecycleChange();
///   }
///
///   @override
///   void dispose() {
///     stopListenOnLifecycleChange();
///     super.dispose();
///   }
///
///   @override
///   void onResume() {
///     // Handle app resume event
///   }
///
///   @override
///   void onHide() {
///     // Handle app hide event
///   }
///
///   // ... other lifecycle methods
/// }
/// ```
mixin LifecycleMixin {
  /// An instance of [AppLifecycleListener] to listen to app lifecycle events.
  AppLifecycleListener? _appLifecycleListener;

  /// Starts listening to app lifecycle events.
  ///
  /// This method initializes an `AppLifecycleListener` instance and starts listening to
  /// app lifecycle events. This method should be called in the `initState` method of
  /// the widget.
  @mustCallSuper
  void startListenOnLifecycleChange() {
    _appLifecycleListener ??= AppLifecycleListener(
      onResume: onResume,
      onHide: onHide,
      onPause: onPause,
      onDetach: onDetach,
      onInactive: onInactive,
      onRestart: onRestart,
      onShow: onShow,
      onStateChange: onStateChange,
    );
  }

  /// Stops listening to app lifecycle events.
  ///
  /// This method disposes the `AppLifecycleListener` instance and stops listening to
  /// app lifecycle events. This method should be called in the `dispose` method of
  /// the widget.
  @mustCallSuper
  void stopListenOnLifecycleChange() {
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;
  }

  /// Called when the app is resumed.
  ///
  /// This method can be overridden to handle app resume events.
  /// For example, you can update the UI or refresh data when the app is resumed.
  void onResume() {}

  /// Called when the app is hidden.
  ///
  /// This method can be overridden to handle app hide events.
  /// For example, you can pause tasks or save data when the app is hidden.
  void onHide() {}

  /// Called when the app is paused.
  ///
  /// This method can be overridden to handle app pause events.
  /// For example, you can stop animations or release resources when the app is paused.
  void onPause() {}

  /// Called when the app is detached.
  ///
  /// This method can be overridden to handle app detach events.
  /// This method is called when the widget is removed from the widget tree.
  void onDetach() {}

  /// Called when the app becomes inactive.
  ///
  /// This method can be overridden to handle app inactive events.
  /// This method is called when the app is no longer in the foreground.
  void onInactive() {}

  /// Called when the app is restarted.
  ///
  /// This method can be overridden to handle app restart events.
  /// This method is called when the app is relaunched.
  void onRestart() {}

  /// Called when the app is shown.
  ///
  /// This method can be overridden to handle app show events.
  /// This method is called when the app becomes visible again.
  void onShow() {}

  /// Called when the app lifecycle state changes.
  ///
  /// This method can be overridden to handle app lifecycle state changes.
  /// The `value` parameter contains the current app lifecycle state.
  void onStateChange(AppLifecycleState value) {}
}
