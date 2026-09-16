import 'package:flutter/widgets.dart';

abstract class PaymentNavigator {
  void toPayment(
    BuildContext context, {
    required String orderId,
    required double amount,
  });
}
