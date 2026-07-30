import 'package:flutter_bloc/flutter_bloc.dart';
export 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Blocs in the application.
/// By default, it simply extends Bloc without enforcing complex mechanisms.
/// Developers can add common features (like default error handling, logging, or analytics) here in the future.
abstract class BaseBloc<Event, State> extends Bloc<Event, State> {
  BaseBloc(super.initialState);
}
