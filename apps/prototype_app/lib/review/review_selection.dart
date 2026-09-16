import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';
import 'review_decision_normalizer.dart';
import 'review_mixed_preview.dart';
import 'review_screen_availability.dart';
import 'review_section_compatibility.dart';
import 'review_section_registry.dart';

/// Width at or above which the mix editor and the live preview sit side by side.
const double _widePreviewBreakpoint = 900;

/// Select + Mix client decision workspace.
///
/// It exposes the hierarchical decision model — overall direction → screen
/// inherit/override → section inherit/override — together with an effective
/// result summary and a live mixed preview. Every mutation is delegated to
/// [ReviewController]; the widget never reads or writes serialized review maps
/// directly and derives effective values through
/// [effectiveScreenDirection]/[effectiveSectionDirection]. Preview/navigation
/// state is local and never mutates decisions.
class ReviewSelection extends StatefulWidget {
  const ReviewSelection({
    super.key,
    required this.runtime,
    required this.controller,
    required this.fixtures,
  });

  /// Key for the overall direction [RadioGroup].
  static const Key overallGroupKey = Key('review-selection-overall');

  /// Key for a governed screen's direction chooser.
  static Key screenGroupKey(String screenId) =>
      Key('review-selection-screen-$screenId');

  /// Key for a governed section's direction chooser.
  static Key sectionGroupKey(String screenId, String sectionId) =>
      Key('review-selection-section-$screenId-$sectionId');

  /// Key for a governed screen's `Reset screen mix` button.
  static Key resetScreenButtonKey(String screenId) =>
      Key('review-selection-reset-$screenId');

  /// Key for the live mixed preview host.
  static const Key previewHostKey = Key('review-selection-preview');

  /// Key for the preview screen selector.
  static const Key previewScreenSelectorKey =
      Key('review-selection-preview-screen');

  final PrototypeRuntime runtime;
  final ReviewController controller;
  final FixtureRepository fixtures;

  @override
  State<ReviewSelection> createState() => _ReviewSelectionState();
}

class _ReviewSelectionState extends State<ReviewSelection> {
  String? _previewScreenId;

  @override
  Widget build(BuildContext context) {
    final directionIds = ReviewScreenAvailability.orderedDirections(widget.runtime);
    final screens = ReviewScreenAvailability.screens(widget.runtime);
    if (screens.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No governed screens are available for this client.'),
        ),
      );
    }
    final previewScreenId =
        (_previewScreenId != null && screens.contains(_previewScreenId))
            ? _previewScreenId!
            : screens.first;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final editor = _buildEditor(context, directionIds, screens);
        final preview = _buildPreview(context, screens, previewScreenId);
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _widePreviewBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: editor),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 2, child: preview),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: editor),
                const Divider(height: 1),
                SizedBox(height: 300, child: preview),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEditor(
    BuildContext context,
    List<String> directionIds,
    List<String> screens,
  ) {
    final state = widget.controller.state;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Overall selection',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Overall: ${state.selectedDirection?.toUpperCase() ?? 'Not selected'}'),
          const SizedBox(height: 8),
          RadioGroup<String?>(
            key: ReviewSelection.overallGroupKey,
            groupValue: state.selectedDirection,
            onChanged: widget.controller.selectDirection,
            child: Column(
              children: [
                const RadioListTile<String?>(
                  value: null,
                  title: Text('No selection yet'),
                  dense: true,
                ),
                for (final id in directionIds)
                  RadioListTile<String?>(
                    value: id,
                    title: Text(widget.runtime.directions[id]!.name),
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
                  : () => widget.controller.selectDirection(null),
              child: const Text('Clear selection'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Screen mix', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final screenId in screens)
            _buildScreenBlock(context, screenId, directionIds),
        ],
      ),
    );
  }

  Widget _buildScreenBlock(
    BuildContext context,
    String screenId,
    List<String> directionIds,
  ) {
    final state = widget.controller.state;
    final screenLabel = ReviewScreenAvailability.labelFor(screenId);
    final explicit = state.screenSelections[screenId]?.direction;
    final effective = effectiveScreenDirection(state, screenId);
    final base = effective == null
        ? 'Base: Not selected'
        : 'Base: ${effective.toUpperCase()} '
            '(${explicit != null ? 'Explicit' : 'Inherited'})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(screenLabel, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        RadioGroup<String?>(
          key: ReviewSelection.screenGroupKey(screenId),
          groupValue: explicit,
          onChanged: (value) {
            if (value == null) {
              widget.controller.clearScreenDirection(screenId);
            } else {
              widget.controller.setScreenDirection(screenId, value);
            }
          },
          child: Column(
            children: [
              RadioListTile<String?>(
                value: null,
                title: Text(
                  'Inherit from overall '
                  '(${state.selectedDirection?.toUpperCase() ?? 'none'})',
                ),
                enabled: true,
                dense: true,
              ),
              for (final id in directionIds)
                _buildScreenDirectionOption(screenId, screenLabel, id),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(base),
        const SizedBox(height: 12),
        for (final section
            in ReviewSectionRegistry.sectionsForScreen(screenId))
          _buildSectionBlock(context, screenId, screenLabel, effective, section),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: ReviewSelection.resetScreenButtonKey(screenId),
            onPressed: widget.controller.state.screenSelections[screenId] == null
                ? null
                : () => _confirmReset(screenId, screenLabel),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset screen mix'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildScreenDirectionOption(
    String screenId,
    String screenLabel,
    String directionId,
  ) {
    final declares = ReviewScreenAvailability.isSupported(
      widget.runtime,
      directionId,
      screenId,
    );
    final label = directionId.toUpperCase();
    return RadioListTile<String?>(
      value: directionId,
      title: Text('Direction $label'),
      subtitle:
          declares ? null : Text('Direction $label does not include $screenLabel'),
      enabled: declares,
      dense: true,
    );
  }

  Widget _buildSectionBlock(
    BuildContext context,
    String screenId,
    String screenLabel,
    String? effectiveScreen,
    ReviewSectionDefinition section,
  ) {
    final state = widget.controller.state;
    final explicit = state.screenSelections[screenId]?.sections[section.id];
    final effective = effectiveSectionDirection(state, screenId, section.id);
    final effectiveLine = explicit != null
        ? '${section.label}: ${explicit.toUpperCase()}'
        : '${section.label}: ${effective?.toUpperCase() ?? '—'} (Inherited)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(section.label, style: Theme.of(context).textTheme.labelMedium),
        RadioGroup<String?>(
          key: ReviewSelection.sectionGroupKey(screenId, section.id),
          groupValue: explicit,
          onChanged: (value) {
            if (value == null) {
              widget.controller.clearSectionDirection(screenId, section.id);
            } else {
              widget.controller.setSectionDirection(screenId, section.id, value);
            }
          },
          child: Column(
            children: [
              RadioListTile<String?>(
                value: null,
                title: Text(
                  'Inherit from $screenLabel '
                  '(${effectiveScreen?.toUpperCase() ?? 'none'})',
                ),
                enabled: true,
                dense: true,
              ),
              for (final id in widget.runtime.allowedDirections)
                _buildSectionDirectionOption(
                  screenId,
                  section.id,
                  effectiveScreen,
                  id,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(effectiveLine),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSectionDirectionOption(
    String screenId,
    String sectionId,
    String? effectiveScreen,
    String directionId,
  ) {
    String? reason;
    bool enabled;
    if (effectiveScreen == null) {
      // Mixing requires a resolvable base screen direction; without one the
      // compatibility contract cannot be evaluated.
      enabled = false;
      reason = 'Select an overall direction first';
    } else {
      final result = ReviewSectionCompatibility.evaluate(
        runtime: widget.runtime,
        screenId: screenId,
        sectionId: sectionId,
        sourceDirectionId: directionId,
        baseDirectionId: effectiveScreen,
      );
      enabled = result.allowed;
      reason = result.reason;
    }
    return RadioListTile<String?>(
      value: directionId,
      title: Text('Direction ${directionId.toUpperCase()}'),
      subtitle: reason == null ? null : Text(reason),
      enabled: enabled,
      dense: true,
    );
  }

  Widget _buildPreview(
    BuildContext context,
    List<String> screens,
    String previewScreenId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Live mixed preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            key: ReviewSelection.previewScreenSelectorKey,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final screenId in screens)
                ChoiceChip(
                  label: Text(ReviewScreenAvailability.labelFor(screenId)),
                  selected: screenId == previewScreenId,
                  onSelected: (_) => setState(() => _previewScreenId = screenId),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: KeyedSubtree(
            key: ReviewSelection.previewHostKey,
            child: ReviewMixedPreview(
              runtime: widget.runtime,
              fixtures: widget.fixtures,
              screenId: previewScreenId,
              state: widget.controller.state,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(String screenId, String screenLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset screen mix?'),
        content: Text(
          'This removes the screen direction and all section overrides for '
          '$screenLabel. The screen will inherit the overall direction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.controller.resetScreenMix(screenId);
    }
  }
}
