import 'review_screen_decision.dart';

enum ReviewStatus { inReview, needsRevision, readyForFinalReview }

enum ReviewCommentScope { general, screen }

String reviewStatusToWire(ReviewStatus value) => switch (value) {
      ReviewStatus.inReview => 'in_review',
      ReviewStatus.needsRevision => 'needs_revision',
      ReviewStatus.readyForFinalReview => 'ready_for_final_review',
    };

ReviewStatus reviewStatusFromWire(String value) => switch (value) {
      'in_review' => ReviewStatus.inReview,
      'needs_revision' => ReviewStatus.needsRevision,
      'ready_for_final_review' => ReviewStatus.readyForFinalReview,
      _ => throw FormatException('Unknown review status: $value'),
    };

String reviewCommentScopeToWire(ReviewCommentScope value) => switch (value) {
      ReviewCommentScope.general => 'general',
      ReviewCommentScope.screen => 'screen',
    };

ReviewCommentScope reviewCommentScopeFromWire(String value) => switch (value) {
      'general' => ReviewCommentScope.general,
      'screen' => ReviewCommentScope.screen,
      _ => throw FormatException('Unknown review comment scope: $value'),
    };

final class ReviewComment {
  const ReviewComment({
    required this.id,
    required this.scope,
    required this.text,
    this.screen,
    this.direction,
  });

  final String id;
  final ReviewCommentScope scope;
  final String text;
  final String? screen;
  final String? direction;

  factory ReviewComment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing review comment id');
    }
    final scopeValue = json['scope'];
    if (scopeValue is! String) {
      throw const FormatException('Missing review comment scope');
    }
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('Missing review comment text');
    }
    final screen = json['screen'];
    if (screen != null && screen is! String) {
      throw const FormatException('Invalid review comment screen');
    }
    final direction = json['direction'];
    if (direction != null && direction is! String) {
      throw const FormatException('Invalid review comment direction');
    }
    return ReviewComment(
      id: id,
      scope: reviewCommentScopeFromWire(scopeValue),
      text: text,
      screen: screen as String?,
      direction: direction as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scope': reviewCommentScopeToWire(scope),
      'text': text,
      if (screen != null) 'screen': screen,
      if (direction != null) 'direction': direction,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewComment &&
        other.id == id &&
        other.scope == scope &&
        other.text == text &&
        other.screen == screen &&
        other.direction == direction;
  }

  @override
  int get hashCode => Object.hash(id, scope, text, screen, direction);
}

final class ReviewState {
  ReviewState({
    required this.version,
    required this.clientId,
    required this.reviewRound,
    required this.status,
    required this.selectedDirection,
    required Map<String, ReviewScreenDecision> screenSelections,
    required List<ReviewComment> comments,
    List<String> feedbackIds = const <String>[],
  })  : screenSelections =
            Map<String, ReviewScreenDecision>.unmodifiable(screenSelections),
        comments = List<ReviewComment>.unmodifiable(comments),
        feedbackIds = List<String>.unmodifiable(feedbackIds);

  static const int currentVersion = 2;

  final int version;
  final String clientId;
  final int reviewRound;
  final ReviewStatus status;
  final String? selectedDirection;
  final Map<String, ReviewScreenDecision> screenSelections;
  final List<ReviewComment> comments;

  /// References to the feedback relevant to the current review.
  ///
  /// ReviewState stores stable feedback ids only; [FeedbackRecord] remains the
  /// sole authority over feedback content and history.
  final List<String> feedbackIds;

  factory ReviewState.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('Missing review state version');
    }
    if (version != 1 && version != currentVersion) {
      throw FormatException('Unsupported review state version: $version');
    }
    final clientId = json['client_id'];
    if (clientId is! String || clientId.trim().isEmpty) {
      throw const FormatException('Missing review state client_id');
    }
    final reviewRound = json['review_round'];
    if (reviewRound is! int) {
      throw const FormatException('Review state review_round must be an integer');
    }
    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('Missing review state status');
    }
    if (!json.containsKey('selected_direction')) {
      throw const FormatException('Missing review state selected_direction');
    }
    final selectedDirection = json['selected_direction'];
    if (selectedDirection != null && selectedDirection is! String) {
      throw const FormatException('Invalid review state selected_direction');
    }
    final rawSelections = json['screen_selections'];
    if (rawSelections is! Map) {
      throw const FormatException('Missing review state screen_selections');
    }
    final screenSelections = <String, ReviewScreenDecision>{};
    for (final entry in rawSelections.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String) {
        throw const FormatException('Invalid review state screen selection');
      }
      if (version == 1) {
        // Legacy C.1/C.2 shape: `screen -> direction` string.
        if (value is! String || value.trim().isEmpty) {
          throw const FormatException('Invalid review state screen selection');
        }
        screenSelections[key] = ReviewScreenDecision(direction: value);
      } else {
        if (value is! Map || value.keys.any((key) => key is! String)) {
          throw const FormatException('Invalid review state screen selection');
        }
        screenSelections[key] =
            ReviewScreenDecision.fromJson(value.cast<String, dynamic>());
      }
    }
    final rawComments = json['comments'];
    if (rawComments is! List) {
      throw const FormatException('Missing review state comments');
    }
    final comments = <ReviewComment>[];
    for (final item in rawComments) {
      if (item is! Map) {
        throw const FormatException('Invalid review state comment');
      }
      comments.add(ReviewComment.fromJson(item.cast<String, dynamic>()));
    }
    // Backward-compatible: legacy v1/v2 state without feedback references
    // migrates to an empty list (R2).
    final rawFeedbackIds = json['feedback_ids'];
    if (rawFeedbackIds != null && rawFeedbackIds is! List) {
      throw const FormatException('Invalid review state feedback_ids');
    }
    final feedbackIds = <String>[];
    if (rawFeedbackIds is List) {
      for (final item in rawFeedbackIds) {
        if (item is! String || item.trim().isEmpty) {
          throw const FormatException('Invalid review state feedback id');
        }
        feedbackIds.add(item);
      }
    }
    return ReviewState(
      version: currentVersion,
      clientId: clientId,
      reviewRound: reviewRound,
      status: reviewStatusFromWire(statusValue),
      selectedDirection: selectedDirection as String?,
      screenSelections: screenSelections,
      comments: comments,
      feedbackIds: feedbackIds,
    );
  }

  Map<String, dynamic> toJson() {
    final sortedKeys = screenSelections.keys.toList()..sort();
    return {
      'version': currentVersion,
      'client_id': clientId,
      'review_round': reviewRound,
      'status': reviewStatusToWire(status),
      'selected_direction': selectedDirection,
      'screen_selections': {
        for (final key in sortedKeys) key: screenSelections[key]!.toJson(),
      },
      'comments': [for (final comment in comments) comment.toJson()],
      'feedback_ids': [for (final id in feedbackIds) id],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReviewState) return false;
    if (other.version != version ||
        other.clientId != clientId ||
        other.reviewRound != reviewRound ||
        other.status != status ||
        other.selectedDirection != selectedDirection) {
      return false;
    }
    return _mapEquals(other.screenSelections, screenSelections) &&
        _listEquals(other.comments, comments) &&
        _stringListEquals(other.feedbackIds, feedbackIds);
  }

  @override
  int get hashCode => Object.hash(
        version,
        clientId,
        reviewRound,
        status,
        selectedDirection,
        Object.hashAllUnordered(
          screenSelections.entries.map((entry) => Object.hash(entry.key, entry.value)),
        ),
        Object.hashAll(comments),
        Object.hashAll(feedbackIds),
      );
}

bool _mapEquals(
  Map<String, ReviewScreenDecision> a,
  Map<String, ReviewScreenDecision> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals(List<ReviewComment> a, List<ReviewComment> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
