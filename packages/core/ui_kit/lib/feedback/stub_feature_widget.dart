import 'package:flutter/material.dart';

/// A standard placeholder widget displayed when navigating to a feature module
/// that is running in Stub mode (e.g., git submodule not initialized or developer
/// does not have access to that team's source repository).
class StubFeatureWidget extends StatelessWidget {
  const StubFeatureWidget({
    super.key,
    required this.featureName,
    this.description,
    this.submoduleRepoUrl,
    this.parameters,
    this.actions,
  });

  /// Name of the feature module (e.g., 'Payment', 'E-Commerce')
  final String featureName;

  /// Custom description explaining the stub status
  final String? description;

  /// Optional git repository URL for the real submodule
  final String? submoduleRepoUrl;

  /// Optional debug parameters passed to the stub (e.g. orderId, amount)
  final Map<String, dynamic>? parameters;

  /// Optional action buttons (e.g. Mock Success, Back)
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status Icon with circular background
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.extension_off_outlined,
                size: 56,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 20),

            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'STUB / PLACEHOLDER MODULE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.amber,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Feature Title
            Text(
              featureName,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description ??
                  'Mã nguồn tính năng này thuộc quyền quản trị của team khác và không có trong bản build này.\nApp Shell đang chạy với Mock Contract để hỗ trợ test độc lập.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),

            if (parameters != null && parameters!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Received Parameters (Mock Scope):',
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...parameters!.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${e.key}: ${e.value}',
                          style: textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (submoduleRepoUrl != null) ...[
              const SizedBox(height: 16),
              Text(
                'Submodule: $submoduleRepoUrl',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
