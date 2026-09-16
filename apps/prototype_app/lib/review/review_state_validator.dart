import '../runtime/prototype_runtime.dart';
import 'review_section_compatibility.dart';
import 'review_section_registry.dart';
import 'review_state.dart';

List<String> validateReviewState(
  ReviewState state,
  PrototypeRuntime runtime, {
  required Set<String> screenIds,
}) {
  final errors = <String>[];
  final directionIds = runtime.directions.keys.toSet();

  if (state.version != ReviewState.currentVersion) {
    errors.add('unsupported review state version: ${state.version}');
  }

  if (state.clientId != runtime.clientId) {
    errors.add(
      'review state client ${state.clientId} does not match runtime client ${runtime.clientId}',
    );
  }

  if (state.reviewRound < 1) {
    errors.add('invalid review round: ${state.reviewRound}');
  }

  final selectedDirection = state.selectedDirection;
  if (selectedDirection != null && !directionIds.contains(selectedDirection)) {
    errors.add('selected direction $selectedDirection is not present in runtime directions');
  }

  for (final entry in state.screenSelections.entries) {
    final screenId = entry.key;
    final decision = entry.value;
    if (!screenIds.contains(screenId)) {
      errors.add('unknown screen id: $screenId');
      continue;
    }
    final screenDirection = decision.direction;
    var screenDirectionValid = true;
    if (screenDirection != null) {
      if (!directionIds.contains(screenDirection)) {
        errors.add(
          'screen $screenId direction $screenDirection is not present in runtime directions',
        );
        screenDirectionValid = false;
      } else if (!runtime.directions[screenDirection]!.patterns.contains(screenId)) {
        errors.add(
          'screen $screenId direction $screenDirection does not include this screen',
        );
        screenDirectionValid = false;
      } else if (screenDirection == selectedDirection) {
        errors.add('redundant screen override: $screenId');
      }
    }

    if (decision.direction == null && decision.sections.isEmpty) {
      errors.add('empty screen decision: $screenId');
    }

    // Skip dependent section checks when the screen's own direction is invalid;
    // section findings would otherwise be misleading cascades.
    if (!screenDirectionValid) {
      continue;
    }

    final effectiveScreen = screenDirection ?? selectedDirection;
    for (final section in decision.sections.entries) {
      final sectionId = section.key;
      final sectionDirection = section.value;
      final definition = ReviewSectionRegistry.definition(sectionId);
      if (definition == null) {
        errors.add('unknown section id: $sectionId');
        continue;
      }
      if (definition.screenId != screenId) {
        errors.add('section $sectionId does not belong to screen $screenId');
        continue;
      }
      if (effectiveScreen == null) {
        errors.add('section $sectionId has no effective screen direction');
        continue;
      }
      if (sectionDirection == effectiveScreen) {
        errors.add('redundant section override: $sectionId');
        continue;
      }
      final result = ReviewSectionCompatibility.evaluate(
        runtime: runtime,
        screenId: screenId,
        sectionId: sectionId,
        sourceDirectionId: sectionDirection,
        baseDirectionId: effectiveScreen,
      );
      if (!result.allowed) {
        errors.add(
          'section $sectionId source $sectionDirection is not mixable: ${result.reason}',
        );
      }
    }
  }

  final seenIds = <String>{};
  final duplicateIds = <String>{};
  for (final comment in state.comments) {
    if (!seenIds.add(comment.id)) {
      duplicateIds.add(comment.id);
    }
  }
  for (final id in duplicateIds) {
    errors.add('duplicate comment id: $id');
  }

  for (final comment in state.comments) {
    final screen = comment.screen;
    if (comment.scope == ReviewCommentScope.screen) {
      if (screen == null || screen.trim().isEmpty) {
        errors.add('screen comment ${comment.id} missing screen');
      } else if (!screenIds.contains(screen)) {
        errors.add('unknown screen id: $screen');
      }
    }
    final direction = comment.direction;
    if (direction != null && !directionIds.contains(direction)) {
      errors.add('comment ${comment.id} direction $direction is not present in runtime directions');
    }
    if (comment.text.trim().isEmpty) {
      errors.add('comment ${comment.id} has empty text');
    }
  }

  final seenFeedbackIds = <String>{};
  final duplicateFeedbackIds = <String>{};
  for (final id in state.feedbackIds) {
    if (id.trim().isEmpty) {
      errors.add('invalid feedback id: $id');
      continue;
    }
    if (!seenFeedbackIds.add(id)) {
      duplicateFeedbackIds.add(id);
    }
  }
  for (final id in duplicateFeedbackIds) {
    errors.add('duplicate feedback id: $id');
  }

  final unique = errors.toSet().toList()..sort();
  return unique;
}
