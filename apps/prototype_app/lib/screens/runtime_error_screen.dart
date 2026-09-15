import 'package:flutter/material.dart';

import '../runtime/runtime_exception.dart';

/// Governed, client-facing runtime error surface.
///
/// It shows a concise remediation message and the requested client/direction
/// without exposing a stack trace.
class RuntimeErrorScreen extends StatelessWidget {
  const RuntimeErrorScreen({super.key, required this.error});

  final RuntimeException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Unable to load prototype runtime',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(error.message, textAlign: TextAlign.center),
              if (error.clientId != null) ...[
                const SizedBox(height: 12),
                Text('Client: ${error.clientId}'),
              ],
              if (error.directionId != null) Text('Direction: ${error.directionId}'),
            ],
          ),
        ),
      ),
    );
  }
}
