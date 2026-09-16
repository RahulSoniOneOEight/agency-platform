import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'review_comparison_layout.dart';
import 'review_controller.dart';
import 'review_direction_summary.dart';
import 'review_preview.dart';

/// Neutral comparison surface for the runtime's actual client directions.
///
/// The surface is display-only: it presents one [ReviewDirectionSummary] per
/// direction in the runtime's declared `allowedDirections` order and never
/// sorts, scores, ranks, or recommends a direction. Its only persistent effect
/// is the explicit, per-direction `Select this direction` action, which routes
/// through [ReviewController.selectDirection]; previewing a direction (tapping
/// the compact switcher) only changes local ephemeral state.
class ReviewDirectionComparison extends StatefulWidget {
  const ReviewDirectionComparison({
    super.key,
    required this.runtime,
    required this.controller,
  });

  final PrototypeRuntime runtime;
  final ReviewController controller;

  @override
  State<ReviewDirectionComparison> createState() =>
      _ReviewDirectionComparisonState();
}

class _ReviewDirectionComparisonState extends State<ReviewDirectionComparison> {
  late int _activeIndex;
  bool _userPreviewed = false;

  @override
  void initState() {
    super.initState();
    _activeIndex = _previewIndex();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  int _previewIndex() {
    final direction = resolvePreviewDirection(
      widget.runtime,
      widget.controller.state,
    );
    final index = widget.runtime.allowedDirections.indexOf(direction);
    return index < 0 ? 0 : index;
  }

  void _handleControllerChanged() {
    if (_userPreviewed) {
      return;
    }
    final index = _previewIndex();
    if (index != _activeIndex) {
      setState(() => _activeIndex = index);
    }
  }

  void _previewDirection(int index) {
    setState(() {
      _userPreviewed = true;
      _activeIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runtime = widget.runtime;
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selectedDirection = controller.state.selectedDirection;
        final panels = <ReviewComparisonPanel>[
          for (final id in runtime.allowedDirections)
            ReviewComparisonPanel(
              id: id,
              label: id.toUpperCase(),
              child: ReviewDirectionSummary(
                direction: runtime.directions[id]!,
                selected: selectedDirection == id,
                onSelect: () => controller.selectDirection(id),
              ),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Directions comparison',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Compare the actual client directions.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReviewComparisonLayout(
                panels: panels,
                activeIndex: _activeIndex,
                onActiveIndexChanged: _previewDirection,
                allowModeToggle: true,
              ),
            ),
          ],
        );
      },
    );
  }
}
