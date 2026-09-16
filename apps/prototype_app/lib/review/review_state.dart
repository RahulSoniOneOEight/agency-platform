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
  const ReviewState({
    required this.version,
    required this.clientId,
    required this.reviewRound,
    required this.status,
    required this.selectedDirection,
    required this.screenSelections,
    required this.comments,
  });

  static const int currentVersion = 1;

  final int version;
  final String clientId;
  final int reviewRound;
  final ReviewStatus status;
  final String? selectedDirection;
  final Map<String, String> screenSelections;
  final List<ReviewComment> comments;

  factory ReviewState.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('Missing review state version');
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
    final selectedDirection = json['selected_direction'];
    if (selectedDirection != null && selectedDirection is! String) {
      throw const FormatException('Invalid review state selected_direction');
    }
    final rawSelections = json['screen_selections'];
    if (rawSelections is! Map) {
      throw const FormatException('Missing review state screen_selections');
    }
    final screenSelections = <String, String>{};
    for (final entry in rawSelections.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) {
        throw const FormatException('Invalid review state screen selection');
      }
      screenSelections[key] = value;
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
    return ReviewState(
      version: version,
      clientId: clientId,
      reviewRound: reviewRound,
      status: reviewStatusFromWire(statusValue),
      selectedDirection: selectedDirection as String?,
      screenSelections: Map<String, String>.unmodifiable(screenSelections),
      comments: List<ReviewComment>.unmodifiable(comments),
    );
  }

  Map<String, dynamic> toJson() {
    final sortedKeys = screenSelections.keys.toList()..sort();
    return {
      'version': version,
      'client_id': clientId,
      'review_round': reviewRound,
      'status': reviewStatusToWire(status),
      'selected_direction': selectedDirection,
      'screen_selections': {
        for (final key in sortedKeys) key: screenSelections[key],
      },
      'comments': [for (final comment in comments) comment.toJson()],
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
        _listEquals(other.comments, comments);
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
      );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
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
