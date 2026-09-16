import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';
import 'review_state.dart';

/// Read-only review metadata summary.
///
/// Every value is derived from the loaded [PrototypeRuntime] and the injected
/// [ReviewController] state. This screen owns no state and never mutates the
/// runtime bundle.
class ReviewOverview extends StatelessWidget {
  const ReviewOverview({
    super.key,
    required this.runtime,
    required this.controller,
  });

  final PrototypeRuntime runtime;
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Client: ${runtime.clientId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _OverviewRow(label: 'Review round', value: '${state.reviewRound}'),
            _OverviewRow(label: 'Status', value: reviewStatusToWire(state.status)),
            _OverviewRow(
              label: 'Overall direction',
              value: state.selectedDirection ?? 'Not selected',
            ),
            _OverviewRow(
              label: 'Mixed screens',
              value: '${state.screenSelections.length}',
            ),
            _OverviewRow(label: 'Comments', value: '${state.comments.length}'),
          ],
        );
      },
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$label: $value'),
    );
  }
}
