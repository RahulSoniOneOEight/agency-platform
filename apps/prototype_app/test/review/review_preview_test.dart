import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_preview.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRuntime({List<String> directionIds = const ['a', 'b', 'c']}) {
  return PrototypeRuntime.fromMap(canonicalBundle(directionIds: directionIds));
}

ReviewState stateWith(PrototypeRuntime runtime, String? selectedDirection) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: runtime.clientId,
    reviewRound: 1,
    status: ReviewStatus.inReview,
    selectedDirection: selectedDirection,
    screenSelections: const <String, ReviewScreenDecision>{},
    comments: const <ReviewComment>[],
  );
}

void main() {
  test('returns the restored selection when one is present', () {
    final runtime = buildRuntime();
    expect(runtime.defaultDirection, 'a');

    expect(resolvePreviewDirection(runtime, stateWith(runtime, 'c')), 'c');
  });

  test('returns the runtime default only when no selection exists', () {
    final runtime = buildRuntime();

    expect(resolvePreviewDirection(runtime, stateWith(runtime, null)), 'a');
  });
}
