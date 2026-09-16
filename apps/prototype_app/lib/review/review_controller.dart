import 'package:flutter/foundation.dart';

import '../runtime/prototype_runtime.dart';
import 'review_decision_normalizer.dart';
import 'review_repository.dart';
import 'review_screen_decision.dart';
import 'review_screen_registry.dart';
import 'review_section_compatibility.dart';
import 'review_section_registry.dart';
import 'review_state.dart';
import 'review_state_validator.dart';

const Object _unset = Object();

/// The single mutation boundary for hierarchical review decisions.
///
/// Every successful mutation flows through [_apply]: the candidate state is
/// normalized to canonical ReviewState v2, validated, persisted through
/// [ReviewRepository], and only then adopted and broadcast. An invalid mutation
/// throws a [StateError] before any save/notify, leaving state untouched.
final class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.clientId,
    required ReviewRepository repository,
    required PrototypeRuntime runtime,
    ReviewState? initialState,
    List<String> Function(ReviewState state)? validate,
  })  : _repository = repository,
        _runtime = runtime,
        _validate = validate ??
            ((state) => validateReviewState(
                  state,
                  runtime,
                  screenIds: ReviewScreenRegistry.screenIdsFor(runtime),
                )),
        _state = initialState ?? initialReviewState(clientId);

  static ReviewState initialReviewState(String clientId) {
    return ReviewState(
      version: ReviewState.currentVersion,
      clientId: clientId,
      reviewRound: 1,
      status: ReviewStatus.inReview,
      selectedDirection: null,
      screenSelections: const <String, ReviewScreenDecision>{},
      comments: const <ReviewComment>[],
    );
  }

  final String clientId;
  final ReviewRepository _repository;
  final PrototypeRuntime _runtime;
  final List<String> Function(ReviewState state) _validate;

  ReviewState _state;
  List<String> _loadErrors = const [];

  ReviewState get state => _state;

  /// Validation findings from the most recent [load] of persisted state.
  List<String> get loadErrors => _loadErrors;

  Future<void> load() async {
    final persisted = await _repository.load(clientId);
    if (persisted == null) {
      return;
    }
    // Normalize before validating so a valid legacy/over-specified state is
    // migrated and pruned rather than rejected wholesale.
    final normalized = normalizeReviewDecisions(persisted, _runtime);
    final errors = _validate(normalized);
    if (errors.isNotEmpty) {
      // Never adopt persisted state that fails validation; keep the initial
      // state and surface the findings instead of silently using bad data.
      _loadErrors = List<String>.unmodifiable(errors);
      notifyListeners();
      return;
    }
    _loadErrors = const [];
    _state = normalized;
    notifyListeners();
  }

  /// Selects the overall direction; `null` clears the overall decision.
  ///
  /// Normalization prunes any screen/section overrides that the new overall
  /// makes redundant, invalid, or incompatible.
  Future<void> selectDirection(String? directionId) async {
    if (directionId != null && !_runtime.directions.containsKey(directionId)) {
      throw StateError(
        'selected direction $directionId is not present in runtime directions',
      );
    }
    await _apply(_copyWith(selectedDirection: directionId));
  }

  /// Sets a screen direction override; `null` clears it and inherits overall.
  ///
  /// A non-null [directionId] must be a runtime direction that actually exposes
  /// [screenId], otherwise the mutation is rejected with a [StateError].
  Future<void> setScreenDirection(String screenId, String? directionId) async {
    if (directionId == null) {
      await clearScreenDirection(screenId);
      return;
    }
    final governedScreens = ReviewScreenRegistry.screenIdsFor(_runtime);
    if (!governedScreens.contains(screenId)) {
      throw StateError('unknown screen id: $screenId');
    }
    if (!_runtime.directions.containsKey(directionId)) {
      throw StateError(
        'screen $screenId direction $directionId is not present in runtime directions',
      );
    }
    if (!_runtime.directions[directionId]!.patterns.contains(screenId)) {
      throw StateError(
        'screen $screenId direction $directionId does not include this screen',
      );
    }
    final selections =
        Map<String, ReviewScreenDecision>.of(_state.screenSelections);
    final existing = selections[screenId];
    selections[screenId] = ReviewScreenDecision(
      direction: directionId,
      sections: existing?.sections ?? const {},
    );
    await _apply(_copyWith(screenSelections: selections));
  }

  /// Clears a screen's direction override while keeping its section overrides.
  ///
  /// Equivalent to [setScreenDirection] with a `null` direction. A no-op when
  /// the screen has no explicit direction; the normalizer then drops the screen
  /// entry entirely when no section overrides remain.
  Future<void> clearScreenDirection(String screenId) async {
    final existing = _state.screenSelections[screenId];
    if (existing == null || existing.direction == null) {
      return;
    }
    final selections =
        Map<String, ReviewScreenDecision>.of(_state.screenSelections);
    selections[screenId] = ReviewScreenDecision(sections: existing.sections);
    await _apply(_copyWith(screenSelections: selections));
  }

  /// Sets a section direction override; `null` clears it and inherits screen.
  ///
  /// The section must be governed for [screenId], a direction must exist, and
  /// the effective screen direction must be resolvable. A non-null
  /// [directionId] must be available and render-compatible, otherwise the
  /// mutation is rejected with a [StateError] carrying the compatibility reason.
  Future<void> setSectionDirection(
    String screenId,
    String sectionId,
    String? directionId,
  ) async {
    final governedScreens = ReviewScreenRegistry.screenIdsFor(_runtime);
    if (!governedScreens.contains(screenId)) {
      throw StateError('unknown screen id: $screenId');
    }
    final definition = ReviewSectionRegistry.definition(sectionId);
    if (definition == null || definition.screenId != screenId) {
      throw StateError('section $sectionId does not belong to screen $screenId');
    }
    if (directionId == null) {
      await _clearSection(screenId, sectionId);
      return;
    }
    if (!_runtime.directions.containsKey(directionId)) {
      throw StateError(
        'section $sectionId source $directionId is not present in runtime directions',
      );
    }
    final effectiveScreen = effectiveScreenDirection(_state, screenId);
    if (effectiveScreen == null) {
      throw StateError('section $sectionId has no effective screen direction');
    }
    final result = ReviewSectionCompatibility.evaluate(
      runtime: _runtime,
      screenId: screenId,
      sectionId: sectionId,
      sourceDirectionId: directionId,
      baseDirectionId: effectiveScreen,
    );
    if (!result.allowed) {
      throw StateError(result.reason ?? 'section $sectionId is not compatible');
    }
    final selections =
        Map<String, ReviewScreenDecision>.of(_state.screenSelections);
    final existing = selections[screenId];
    final sections = Map<String, String>.of(existing?.sections ?? const {});
    sections[sectionId] = directionId;
    selections[screenId] = ReviewScreenDecision(
      direction: existing?.direction,
      sections: sections,
    );
    await _apply(_copyWith(screenSelections: selections));
  }

  /// Clears a section override so it inherits the effective screen direction.
  ///
  /// Equivalent to [setSectionDirection] with a `null` direction.
  Future<void> clearSectionDirection(String screenId, String sectionId) =>
      setSectionDirection(screenId, sectionId, null);

  /// Removes the screen's explicit direction and all of its section overrides,
  /// so the screen inherits the overall selected direction again.
  Future<void> resetScreenMix(String screenId) async {
    if (!_state.screenSelections.containsKey(screenId)) {
      return;
    }
    final selections =
        Map<String, ReviewScreenDecision>.of(_state.screenSelections)
          ..remove(screenId);
    await _apply(_copyWith(screenSelections: selections));
  }

  Future<void> addComment(ReviewComment comment) async {
    if (_state.comments.any((existing) => existing.id == comment.id)) {
      throw StateError('Comment with id "${comment.id}" already exists');
    }
    await _apply(
      _copyWith(comments: <ReviewComment>[..._state.comments, comment]),
    );
  }

  Future<void> updateComment(ReviewComment comment) async {
    final index = _state.comments.indexWhere((existing) => existing.id == comment.id);
    if (index < 0) {
      throw StateError('Comment with id "${comment.id}" does not exist');
    }
    final comments = List<ReviewComment>.of(_state.comments);
    comments[index] = comment;
    await _apply(_copyWith(comments: comments));
  }

  Future<void> setStatus(ReviewStatus status) async {
    await _apply(_copyWith(status: status));
  }

  Future<void> advanceRound() async {
    final next = _state.reviewRound + 1;
    await _apply(_copyWith(reviewRound: next < 1 ? 1 : next));
  }

  Future<void> _clearSection(String screenId, String sectionId) async {
    final existing = _state.screenSelections[screenId];
    if (existing == null || !existing.sections.containsKey(sectionId)) {
      return;
    }
    final selections =
        Map<String, ReviewScreenDecision>.of(_state.screenSelections);
    final sections = Map<String, String>.of(existing.sections)..remove(sectionId);
    selections[screenId] = ReviewScreenDecision(
      direction: existing.direction,
      sections: sections,
    );
    await _apply(_copyWith(screenSelections: selections));
  }

  /// The single transactional path for every mutation.
  ///
  /// Normalizes to canonical v2, validates, persists, then adopts and notifies.
  /// Any validation finding aborts before persistence, so an invalid mutation
  /// has zero side effects.
  Future<void> _apply(ReviewState candidate) async {
    final normalized = normalizeReviewDecisions(candidate, _runtime);
    final errors = _validate(normalized);
    if (errors.isNotEmpty) {
      throw StateError(errors.join('\n'));
    }
    await _repository.save(normalized);
    _state = normalized;
    notifyListeners();
  }

  ReviewState _copyWith({
    int? reviewRound,
    ReviewStatus? status,
    Object? selectedDirection = _unset,
    Map<String, ReviewScreenDecision>? screenSelections,
    List<ReviewComment>? comments,
  }) {
    return ReviewState(
      version: _state.version,
      clientId: _state.clientId,
      reviewRound: reviewRound ?? _state.reviewRound,
      status: status ?? _state.status,
      selectedDirection: identical(selectedDirection, _unset)
          ? _state.selectedDirection
          : selectedDirection as String?,
      screenSelections: screenSelections ?? _state.screenSelections,
      comments: comments ?? _state.comments,
    );
  }
}
