import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../presentation/payment_stub_page.dart';

@LazySingleton(as: IFeatureRouteModule)
class PaymentRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [
        GoRoute(
          path: '/payment',
          parentNavigatorKey: NavigatorKeys.rootKey,
          builder: (context, state) {
            final orderId =
                state.uri.queryParameters['orderId'] ?? 'ORD-MOCK-9999';
            final amount =
                double.tryParse(state.uri.queryParameters['amount'] ?? '') ??
                    99.99;
            return PaymentStubPage(
              orderId: orderId,
              amount: amount,
            );
          },
        ),
      ];
}
