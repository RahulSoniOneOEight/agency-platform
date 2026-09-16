import '../runtime/prototype_runtime.dart';
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
    final directionId = entry.value;
    if (!screenIds.contains(screenId)) {
      errors.add('unknown screen id: $screenId');
      continue;
    }
    if (!directionIds.contains(directionId)) {
      errors.add(
        'screen $screenId direction $directionId is not present in runtime directions',
      );
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

  final unique = errors.toSet().toList()..sort();
  return unique;
}
