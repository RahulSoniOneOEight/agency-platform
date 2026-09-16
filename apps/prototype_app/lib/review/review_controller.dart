import 'package:flutter/foundation.dart';

import 'review_repository.dart';
import 'review_state.dart';

const Object _unset = Object();

final class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.clientId,
    required ReviewRepository repository,
    ReviewState? initialState,
  })  : _repository = repository,
        _state = initialState ?? initialReviewState(clientId);

  static ReviewState initialReviewState(String clientId) {
    return ReviewState(
      version: ReviewState.currentVersion,
      clientId: clientId,
      reviewRound: 1,
      status: ReviewStatus.inReview,
      selectedDirection: null,
      screenSelections: const <String, String>{},
      comments: const <ReviewComment>[],
    );
  }

  final String clientId;
  final ReviewRepository _repository;

  ReviewState _state;

  ReviewState get state => _state;

  Future<void> load() async {
    final persisted = await _repository.load(clientId);
    if (persisted != null) {
      _state = persisted;
      notifyListeners();
    }
  }

  Future<void> selectDirection(String? directionId) async {
    _state = _copyWith(selectedDirection: directionId);
    await _persistAndNotify();
  }

  Future<void> selectScreenDirection(String screenId, String directionId) async {
    final selections = Map<String, String>.of(_state.screenSelections);
    selections[screenId] = directionId;
    _state = _copyWith(screenSelections: selections);
    await _persistAndNotify();
  }

  /// Removes a single screen's direction mix; a no-op when it is not mixed.
  Future<void> clearScreenDirection(String screenId) async {
    if (!_state.screenSelections.containsKey(screenId)) {
      return;
    }
    final selections = Map<String, String>.of(_state.screenSelections)
      ..remove(screenId);
    _state = _copyWith(screenSelections: selections);
    await _persistAndNotify();
  }

  Future<void> addComment(ReviewComment comment) async {
    if (_state.comments.any((existing) => existing.id == comment.id)) {
      throw StateError('Comment with id "${comment.id}" already exists');
    }
    _state = _copyWith(comments: <ReviewComment>[..._state.comments, comment]);
    await _persistAndNotify();
  }

  Future<void> updateComment(ReviewComment comment) async {
    final index = _state.comments.indexWhere((existing) => existing.id == comment.id);
    if (index < 0) {
      throw StateError('Comment with id "${comment.id}" does not exist');
    }
    final comments = List<ReviewComment>.of(_state.comments);
    comments[index] = comment;
    _state = _copyWith(comments: comments);
    await _persistAndNotify();
  }

  Future<void> setStatus(ReviewStatus status) async {
    _state = _copyWith(status: status);
    await _persistAndNotify();
  }

  Future<void> advanceRound() async {
    final next = _state.reviewRound + 1;
    _state = _copyWith(reviewRound: next < 1 ? 1 : next);
    await _persistAndNotify();
  }

  Future<void> _persistAndNotify() async {
    await _repository.save(_state);
    notifyListeners();
  }

  ReviewState _copyWith({
    int? reviewRound,
    ReviewStatus? status,
    Object? selectedDirection = _unset,
    Map<String, String>? screenSelections,
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
