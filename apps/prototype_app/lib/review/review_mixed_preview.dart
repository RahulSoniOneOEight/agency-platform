import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../direction/prototype_direction.dart';
import '../registry/prototype_registry.dart';
import '../runtime/prototype_runtime.dart';
import 'review_decision_normalizer.dart';
import 'review_state.dart';

/// Ephemeral mixed-preview renderer for one governed screen.
///
/// The base screen shell/layout is the effective screen direction; inherited
/// sections render under the base direction's resolved theme; an explicit
/// section override renders the SAME shared section widget built for the source
/// direction, wrapped in that direction's resolved theme. Nested theming is
/// scoped to the overridden section so siblings and the base shell are never
/// contaminated.
///
/// Pure/derived: it reads runtime, fixtures and review state and never mutates
/// them, persists anything, or writes a synthetic runtime.
class ReviewMixedPreview extends StatelessWidget {
  const ReviewMixedPreview({
    super.key,
    required this.runtime,
    required this.fixtures,
    required this.screenId,
    required this.state,
  });

  final PrototypeRuntime runtime;
  final FixtureRepository fixtures;
  final String screenId;
  final ReviewState state;

  static Key sectionKey(String sectionId) => Key('review-mixed-section-$sectionId');
  static Key overrideThemeKey(String sectionId) =>
      Key('review-mixed-override-$sectionId');

  static const Key noBaseKey = Key('review-mixed-no-base');

  @override
  Widget build(BuildContext context) {
    final baseDirectionId = effectiveScreenDirection(state, screenId);
    final baseDirection =
        baseDirectionId == null ? null : runtime.directions[baseDirectionId];
    if (baseDirectionId == null || baseDirection == null) {
      return const Center(
        key: noBaseKey,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Select an overall direction to preview this screen.'),
        ),
      );
    }

    final baseComposition =
        PrototypeRegistry.compositionFor(screenId, baseDirection, fixtures);
    if (baseComposition == null) {
      // Screen is not composed from sections; render it unmixed.
      return PrototypeRegistry.buildPattern(screenId, baseDirection, fixtures);
    }

    final overrides =
        state.screenSelections[screenId]?.sections ?? const <String, String>{};

    final sections = <PatternSection>[];
    for (final section in baseComposition.sections) {
      final sourceId = overrides[section.id];
      if (sourceId == null || sourceId == baseDirectionId) {
        sections.add(_keyed(section.id, section.child));
        continue;
      }

      final sourceDirection = runtime.directions[sourceId];
      final sourceChild = sourceDirection == null
          ? null
          : _sectionChildFor(screenId, section.id, sourceDirection);
      if (sourceChild == null) {
        // Defensive: an unresolved override falls back to the base section.
        sections.add(_keyed(section.id, section.child));
        continue;
      }

      sections.add(
        _keyed(
          section.id,
          KeyedSubtree(
            key: overrideThemeKey(section.id),
            child: Theme(
              data: AgencyTheme.light(runtime.themeForDirection(sourceId)),
              child: sourceChild,
            ),
          ),
        ),
      );
    }

    return Theme(
      data: AgencyTheme.light(runtime.themeForDirection(baseDirectionId)),
      child: buildPatternComposition(
        PatternComposition(
          title: baseComposition.title,
          subtitle: baseComposition.subtitle,
          density: baseComposition.density,
          sections: sections,
        ),
      ),
    );
  }

  PatternSection _keyed(String id, Widget child) =>
      PatternSection(id: id, child: KeyedSubtree(key: sectionKey(id), child: child));

  Widget? _sectionChildFor(
    String screenId,
    String sectionId,
    PrototypeDirection sourceDirection,
  ) {
    final composition =
        PrototypeRegistry.compositionFor(screenId, sourceDirection, fixtures);
    if (composition == null) {
      return null;
    }
    for (final section in composition.sections) {
      if (section.id == sectionId) {
        return section.child;
      }
    }
    return null;
  }
}
