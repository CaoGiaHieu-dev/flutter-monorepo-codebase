import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class PaymentStubPage extends StatelessWidget {
  const PaymentStubPage({
    super.key,
    this.orderId = 'ORD-MOCK-9999',
    this.amount = 99.99,
  });

  final String orderId;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Module (Stub)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: StubFeatureWidget(
          featureName: 'Payment & Wallet Gateway',
          submoduleRepoUrl: 'git@github.com:company/feature_payment_private.git',
          parameters: {
            'orderId': orderId,
            'amount': '\$$amount USD',
            'status': 'MOCK_PENDING',
          },
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Mock Payment Success triggered!'),
                    backgroundColor: Colors.green,
                  ),
                );
                context.pop();
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Simulate Success (Mock)'),
            ),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back to App'),
            ),
          ],
        ),
      ),
    );
  }
}
