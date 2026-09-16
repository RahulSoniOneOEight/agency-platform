import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../runtime/prototype_runtime.dart';
import 'review_comparison_host.dart';
import 'review_comparison_layout.dart';
import 'review_controller.dart';
import 'review_preview.dart';
import 'review_screen_availability.dart';

/// Comparison surface for the same governed screen across runtime directions.
///
/// It reuses the existing client renderer ([ReviewComparisonHost] →
/// [PrototypeRegistry]) and never duplicates screen code. Availability is
/// explicit per `(screen, direction)` pair: an unsupported pair renders the
/// neutral unavailable state and never a substituted screen or direction.
///
/// Viewing a screen is display-only and has no selection side effects: the
/// surface holds only ephemeral local preview state and never mutates the
/// injected [ReviewController].
class ReviewScreenComparison extends StatefulWidget {
  const ReviewScreenComparison({
    super.key,
    required this.runtime,
    required this.fixtures,
    required this.controller,
  });

  final PrototypeRuntime runtime;
  final FixtureRepository fixtures;
  final ReviewController controller;

  static const Key screenSelectorKey = Key('review-screen-comparison-selector');
  static Key screenChipKey(String screenId) => Key('review-screen-chip-$screenId');
  static Key unavailableKey(String directionId) =>
      Key('review-screen-unavailable-$directionId');

  @override
  State<ReviewScreenComparison> createState() => _ReviewScreenComparisonState();
}

class _ReviewScreenComparisonState extends State<ReviewScreenComparison> {
  late String _screenId;
  late int _activeIndex;
  bool _userPreviewed = false;

  @override
  void initState() {
    super.initState();
    _screenId = ReviewScreenAvailability.screens(widget.runtime).first;
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
    final screenIds = ReviewScreenAvailability.screens(runtime);

    final panels = <ReviewComparisonPanel>[
      for (final directionId in runtime.allowedDirections)
        ReviewComparisonPanel(
          id: directionId,
          label: directionId.toUpperCase(),
          child: _DirectionPanel(
            directionId: directionId,
            screenId: _screenId,
            runtime: runtime,
            fixtures: widget.fixtures,
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
              Text('Screen comparison', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Compare the same screen across directions.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                key: ReviewScreenComparison.screenSelectorKey,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final screenId in screenIds)
                    ChoiceChip(
                      key: ReviewScreenComparison.screenChipKey(screenId),
                      label: Text(ReviewScreenAvailability.labelFor(screenId)),
                      selected: screenId == _screenId,
                      onSelected: (_) => setState(() => _screenId = screenId),
                    ),
                ],
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
  }
}

/// One direction's panel: a compact identity header plus the evaluated body.
///
/// The body is the real client screen only when the direction declares the
/// selected governed screen; otherwise it is the neutral unavailable state.
class _DirectionPanel extends StatelessWidget {
  const _DirectionPanel({
    required this.directionId,
    required this.screenId,
    required this.runtime,
    required this.fixtures,
  });

  final String directionId;
  final String screenId;
  final PrototypeRuntime runtime;
  final FixtureRepository fixtures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = runtime.directions[directionId]!;
    final supported =
        ReviewScreenAvailability.isSupported(runtime, directionId, screenId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                directionId.toUpperCase(),
                style: theme.textTheme.labelLarge,
              ),
              Text(direction.name, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        Expanded(
          child: supported
              ? ReviewComparisonHost(
                  runtime: runtime,
                  fixtures: fixtures,
                  directionId: directionId,
                  screenId: screenId,
                )
              : _Unavailable(
                  key: ReviewScreenComparison.unavailableKey(directionId),
                  directionId: directionId,
                ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({super.key, required this.directionId});

  final String directionId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'This screen is not part of Direction ${directionId.toUpperCase()}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
