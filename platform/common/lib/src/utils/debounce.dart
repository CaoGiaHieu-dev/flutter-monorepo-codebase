import 'dart:async';

import 'package:flutter/foundation.dart';

class _EasyDebounceOperation {
  VoidCallback callback;
  Timer timer;
  _EasyDebounceOperation(this.callback, this.timer);
}

class EasyDebounce {
  const EasyDebounce._();
  static final Map<String, _EasyDebounceOperation> _operations = {};
  static void debounce(String tag, Duration duration, VoidCallback onExecute) {
    if (duration == Duration.zero) {
      _operations[tag]?.timer.cancel();
      _operations.remove(tag);
      onExecute();
    } else {
      _operations[tag]?.timer.cancel();

      _operations[tag] = _EasyDebounceOperation(
        onExecute,
        Timer(duration, () {
          _operations[tag]?.timer.cancel();
          _operations.remove(tag);

          onExecute();
        }),
      );
    }
  }

  static void fire(String tag) {
    _operations[tag]?.callback();
  }

  static void cancel(String tag) {
    _operations[tag]?.timer.cancel();
    _operations.remove(tag);
  }

  static void cancelAll() {
    for (final operation in _operations.values) {
      operation.timer.cancel();
    }
    _operations.clear();
  }

  static int count() {
    return _operations.length;
  }
}
