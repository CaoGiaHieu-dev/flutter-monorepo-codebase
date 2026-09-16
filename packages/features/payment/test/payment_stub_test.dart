import 'package:feature_payment/feature_payment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('PaymentStub Tests', () {
    test('PaymentRouteModule declares /payment route correctly', () {
      final module = PaymentRouteModule();
      expect(module.routes, isNotEmpty);
      expect(module.routes.first, isA<RouteBase>());
    });

    testWidgets('PaymentStubPage renders stub placeholder information',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaymentStubPage(
            orderId: 'ORD-TEST-123',
            amount: 49.99,
          ),
        ),
      );

      // Verify Stub indicator and Feature Title
      expect(find.text('STUB / PLACEHOLDER MODULE'), findsOneWidget);
      expect(find.text('Payment & Wallet Gateway'), findsOneWidget);
      expect(find.textContaining('ORD-TEST-123'), findsOneWidget);
      expect(find.textContaining('49.99'), findsOneWidget);
    });
  });
}
