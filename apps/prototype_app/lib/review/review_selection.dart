import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';
import 'review_screen_registry.dart';

/// Overall direction selection plus the per-screen direction mix editor.
///
/// This screen edits review state only. The overall control lists exactly the
/// runtime directions and exposes an explicit `No selection yet` state; it never
/// initializes from the first runtime direction or the runtime's declared
/// `default_direction`. Each governed screen gets a direction chooser sourced
/// from the same runtime directions, and choosing a mix persists through
/// [ReviewController] without ever mutating the runtime direction definitions.
class ReviewSelection extends StatelessWidget {
  const ReviewSelection({
    super.key,
    required this.runtime,
    required this.controller,
  });

  /// Key for the overall direction [RadioGroup].
  static const Key overallGroupKey = Key('review-selection-overall');

  /// Key for a governed screen's direction chooser.
  static Key screenGroupKey(String screenId) =>
      Key('review-selection-screen-$screenId');

  final PrototypeRuntime runtime;
  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    final directionIds = runtime.allowedDirections;
    final screenIds = ReviewScreenRegistry.screenIdsFor(runtime).toList()..sort();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final sortedSelections = state.screenSelections.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Overall selection',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text('Overall direction: ${state.selectedDirection ?? 'Not selected'}'),
              const SizedBox(height: 8),
              RadioGroup<String?>(
                key: overallGroupKey,
                groupValue: state.selectedDirection,
                onChanged: controller.selectDirection,
                child: Column(
                  children: [
                    const RadioListTile<String?>(
                      value: null,
                      title: Text('No selection yet'),
                    ),
                    for (final id in directionIds)
                      RadioListTile<String?>(
                        value: id,
                        title: Text(runtime.directions[id]!.name),
                        subtitle: Text(id),
                        dense: true,
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: state.selectedDirection == null
                      ? null
                      : () => controller.selectDirection(null),
                  child: const Text('Clear selection'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Screen mix', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (sortedSelections.isEmpty)
                const Text('No screens mixed yet.')
              else
                for (final entry in sortedSelections)
                  Text('${entry.key} → ${entry.value.direction}'),
              const SizedBox(height: 12),
              for (final screenId in screenIds) ...[
                Text(
                  ReviewScreenRegistry.labelFor(screenId),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  key: screenGroupKey(screenId),
                  segments: [
                    for (final id in directionIds)
                      ButtonSegment<String>(
                        value: id,
                        label: Text(id.toUpperCase()),
                      ),
                  ],
                  selected: state.screenSelections.containsKey(screenId)
                      ? <String>{
                          if (state.screenSelections[screenId]!.direction != null)
                            state.screenSelections[screenId]!.direction!,
                        }
                      : const <String>{},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      controller.clearScreenDirection(screenId);
                    } else {
                      controller.selectScreenDirection(screenId, selection.first);
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}
