import '../runtime/prototype_runtime.dart';
import 'review_screen_decision.dart';
import 'review_section_compatibility.dart';
import 'review_section_registry.dart';
import 'review_state.dart';

/// The effective direction for [screenId]: its explicit override when present,
/// otherwise the overall [ReviewState.selectedDirection] (possibly `null`).
String? effectiveScreenDirection(ReviewState state, String screenId) {
  return state.screenSelections[screenId]?.direction ?? state.selectedDirection;
}

/// The effective direction for a governed section: its explicit override when
/// present, otherwise the effective screen direction it inherits from.
String? effectiveSectionDirection(
  ReviewState state,
  String screenId,
  String sectionId,
) {
  return state.screenSelections[screenId]?.sections[sectionId] ??
      effectiveScreenDirection(state, screenId);
}

/// Returns a new canonical ReviewState v2 containing only explicit, valid,
/// non-redundant, render-compatible overrides.
///
/// Pure: neither [state] nor [runtime] is mutated. Screen keys and section keys
/// are processed in sorted order, so the result is deterministic and idempotent.
ReviewState normalizeReviewDecisions(
  ReviewState state,
  PrototypeRuntime runtime,
) {
  final selectedDirection = state.selectedDirection;
  final screenKeys = state.screenSelections.keys.toList()..sort();
  final normalizedScreens = <String, ReviewScreenDecision>{};

  for (final screenId in screenKeys) {
    final decision = state.screenSelections[screenId]!;

    // Rule 1: a screen override equal to the overall direction is redundant.
    // Never invent a direction when the overall selection is null.
    var direction = decision.direction;
    if (direction != null && direction == selectedDirection) {
      direction = null;
    }
    final effectiveScreen = direction ?? selectedDirection;

    final sections = <String, String>{};
    final sectionKeys = decision.sections.keys.toList()..sort();
    for (final sectionId in sectionKeys) {
      final source = decision.sections[sectionId]!;

      // Rules 2 & 4: drop redundant sections, unknown/wrong-screen sections,
      // and anything that cannot be resolved to an effective base direction.
      final definition = ReviewSectionRegistry.definition(sectionId);
      if (definition == null || definition.screenId != screenId) {
        continue;
      }
      if (effectiveScreen == null) {
        continue;
      }
      if (source == effectiveScreen) {
        continue;
      }
      final result = ReviewSectionCompatibility.evaluate(
        runtime: runtime,
        screenId: screenId,
        sectionId: sectionId,
        sourceDirectionId: source,
        baseDirectionId: effectiveScreen,
      );
      if (!result.allowed) {
        continue;
      }
      sections[sectionId] = source;
    }

    // Rule 3: drop a screen entry with no direction and no surviving sections.
    if (direction == null && sections.isEmpty) {
      continue;
    }
    normalizedScreens[screenId] = ReviewScreenDecision(
      direction: direction,
      sections: sections,
    );
  }

  // Rule 4: everything except the normalized screen selections is preserved.
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: state.clientId,
    reviewRound: state.reviewRound,
    status: state.status,
    selectedDirection: selectedDirection,
    screenSelections: normalizedScreens,
    comments: state.comments,
  );
}
