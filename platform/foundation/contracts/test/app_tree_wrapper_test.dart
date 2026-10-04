import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _DefaultOrderWrapper extends IAppTreeWrapper {
  @override
  Widget wrap(BuildContext context, Widget child) => child;
}

void main() {
  test('a wrapper that does not choose an order sits at 0', () {
    // The shell folds wrappers by `order`; 0 is the documented default.
    expect(_DefaultOrderWrapper().order, 0);
  });
}
