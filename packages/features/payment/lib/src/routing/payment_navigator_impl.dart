import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: PaymentNavigator)
class PaymentNavigatorImpl implements PaymentNavigator {
  @override
  void toPayment(
    BuildContext context, {
    required String orderId,
    required double amount,
  }) {
    context.push(
      '/payment?orderId=${Uri.encodeComponent(orderId)}&amount=$amount',
    );
  }
}
