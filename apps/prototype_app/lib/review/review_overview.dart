import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';
import 'review_state.dart';

/// Review metadata summary plus the C.1 round/status controls.
///
/// Every value is derived from the loaded [PrototypeRuntime] and the injected
/// [ReviewController] state. The explicit advance action is deterministic
/// (`round + 1`) with no workflow/approval transition logic, and the status
/// control offers exactly the three C.1 lifecycle statuses; neither is an
/// approval action. This screen never mutates the runtime bundle.
class ReviewOverview extends StatelessWidget {
  const ReviewOverview({
    super.key,
    required this.runtime,
    required this.controller,
  });

  /// Explicit review-round advancement action.
  static const Key advanceRoundButtonKey = Key('review-overview-advance-round');

  /// C.1 status control.
  static const Key statusControlKey = Key('review-overview-status');

  final PrototypeRuntime runtime;
  final ReviewController controller;

  /// Explicit confirmation before the (irreversible) round advancement.
  Future<void> _confirmAdvanceRound(BuildContext context) async {
    final round = controller.state.reviewRound;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Advance review round?'),
        content: Text('Move from round $round to round ${round + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Advance'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.advanceRound();
    }
  }

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
            _OverviewRow(
                label: 'Status', value: reviewStatusToWire(state.status)),
            _OverviewRow(
              label: 'Overall direction',
              value: state.selectedDirection ?? 'Not selected',
            ),
            _OverviewRow(
              label: 'Mixed screens',
              value: '${state.screenSelections.length}',
            ),
            _OverviewRow(label: 'Comments', value: '${state.comments.length}'),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: advanceRoundButtonKey,
                onPressed: () => _confirmAdvanceRound(context),
                icon: const Icon(Icons.skip_next),
                label: const Text('Advance review round'),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Review status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ReviewStatus>(
              key: statusControlKey,
              segments: [
                for (final status in ReviewStatus.values)
                  ButtonSegment<ReviewStatus>(
                    value: status,
                    label: Text(reviewStatusToWire(status)),
                  ),
              ],
              selected: {state.status},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  controller.setStatus(selection.first),
            ),
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
