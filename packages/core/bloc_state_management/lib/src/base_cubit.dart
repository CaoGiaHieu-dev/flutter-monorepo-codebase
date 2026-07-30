import 'package:flutter_bloc/flutter_bloc.dart';

/// Base class for all Cubits in the application.
/// By default, it simply extends Cubit without enforcing complex mechanisms.
/// Developers can add common features (like default error handling, logging, or analytics) here in the future.
abstract class BaseCubit<State> extends Cubit<State> {
  BaseCubit(super.initialState);
}
