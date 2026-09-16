/// Lightweight operational index for file-backed review artifacts.
///
/// The index lists ids/versions/current refs for fast lookup. It is explicitly
/// **not** authoritative over record contents: the immutable feedback, batch,
/// and approval files remain the source of truth, and a stale/missing index can
/// always be rebuilt from them.
library;

List<String> _sortedStrings(List<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (value.trim().isEmpty) {
      throw const FormatException('Review index id must not be blank');
    }
    if (!seen.add(value)) {
      throw FormatException('Duplicate review index id: $value');
    }
  }
  return values.toList()..sort();
}

List<int> _sortedInts(List<int> values) {
  final seen = <int>{};
  for (final value in values) {
    if (value < 1) {
      throw const FormatException('Review index version must be positive');
    }
    if (!seen.add(value)) {
      throw FormatException('Duplicate review index version: $value');
    }
  }
  return values.toList()..sort();
}

final class ReviewIndex {
  ReviewIndex({
    required this.clientId,
    this.reviewRound,
    List<String> feedbackIds = const <String>[],
    List<String> batchIds = const <String>[],
    List<int> approvalVersions = const <int>[],
  })  : feedbackIds = List<String>.unmodifiable(_sortedStrings(feedbackIds)),
        batchIds = List<String>.unmodifiable(_sortedStrings(batchIds)),
        approvalVersions =
            List<int>.unmodifiable(_sortedInts(approvalVersions)) {
    if (clientId.trim().isEmpty) {
      throw const FormatException('Review index client id is required');
    }
    if (reviewRound != null && reviewRound! < 1) {
      throw const FormatException('Review index round must be positive');
    }
  }

  final String clientId;
  final int? reviewRound;
  final List<String> feedbackIds;
  final List<String> batchIds;
  final List<int> approvalVersions;

  /// The highest approval version recorded, or `null` when none exist.
  int? get currentApprovalVersion =>
      approvalVersions.isEmpty ? null : approvalVersions.last;

  factory ReviewIndex.fromJson(Map<String, dynamic> json) {
    final clientId = json['client_id'];
    if (clientId is! String) {
      throw const FormatException('Missing review index client id');
    }
    final reviewRound = json['review_round'];
    if (reviewRound != null && reviewRound is! int) {
      throw const FormatException('Invalid review index round');
    }
    return ReviewIndex(
      clientId: clientId,
      reviewRound: reviewRound as int?,
      feedbackIds: _stringList(json['feedback_ids']),
      batchIds: _stringList(json['batch_ids']),
      approvalVersions: _intList(json['approval_versions']),
    );
  }

  /// Deterministic canonical serialization; every key is always present.
  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'review_round': reviewRound,
        'feedback_ids': [...feedbackIds],
        'batch_ids': [...batchIds],
        'approval_versions': [...approvalVersions],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewIndex &&
        other.clientId == clientId &&
        other.reviewRound == reviewRound &&
        _listEquals(other.feedbackIds, feedbackIds) &&
        _listEquals(other.batchIds, batchIds) &&
        _listEquals(other.approvalVersions, approvalVersions);
  }

  @override
  int get hashCode => Object.hash(
        clientId,
        reviewRound,
        Object.hashAll(feedbackIds),
        Object.hashAll(batchIds),
        Object.hashAll(approvalVersions),
      );
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw const FormatException('Invalid review index list');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw const FormatException('Invalid review index id');
    }
    result.add(item);
  }
  return result;
}

List<int> _intList(Object? value) {
  if (value == null) return const <int>[];
  if (value is! List) {
    throw const FormatException('Invalid review index version list');
  }
  final result = <int>[];
  for (final item in value) {
    if (item is! int) {
      throw const FormatException('Invalid review index version');
    }
    result.add(item);
  }
  return result;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Persistence boundary for the operational [ReviewIndex].
abstract interface class ReviewIndexRepository {
  Future<ReviewIndex?> load(String clientId);

  Future<void> save(ReviewIndex index);
}
