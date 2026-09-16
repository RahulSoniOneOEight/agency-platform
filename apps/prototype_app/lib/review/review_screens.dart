import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../runtime/prototype_runtime.dart';
import 'review_comparison_host.dart';
import 'review_screen_registry.dart';

/// Screen selector plus the shared comparison host.
///
/// It lists only governed screen IDs from [ReviewScreenRegistry] and renders the
/// selected screen through [ReviewComparisonHost], which reuses the existing
/// prototype renderer. The local screen/direction choices are preview state; no
/// runtime data is ever mutated.
class ReviewScreens extends StatefulWidget {
  const ReviewScreens({
    super.key,
    required this.runtime,
    required this.fixtures,
  });

  final PrototypeRuntime runtime;
  final FixtureRepository fixtures;

  @override
  State<ReviewScreens> createState() => _ReviewScreensState();
}

class _ReviewScreensState extends State<ReviewScreens> {
  late String _directionId;
  late String _screenId;

  @override
  void initState() {
    super.initState();
    _directionId = widget.runtime.defaultDirection;
    _screenId = _screenIds().first;
  }

  List<String> _screenIds() {
    final ids = ReviewScreenRegistry.screenIdsFor(widget.runtime).toList()..sort();
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final screenIds = _screenIds();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Screen comparison',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text('Preview direction', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: [
                  for (final id in runtime.allowedDirections)
                    ButtonSegment(value: id, label: Text(id.toUpperCase())),
                ],
                selected: {_directionId},
                onSelectionChanged: (selection) =>
                    setState(() => _directionId = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 12),
              Text('Screen', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in screenIds)
                    ChoiceChip(
                      label: Text(ReviewScreenRegistry.labelFor(id)),
                      selected: id == _screenId,
                      onSelected: (_) => setState(() => _screenId = id),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReviewComparisonHost(
            runtime: runtime,
            fixtures: widget.fixtures,
            directionId: _directionId,
            screenId: _screenId,
          ),
        ),
      ],
    );
  }
}
